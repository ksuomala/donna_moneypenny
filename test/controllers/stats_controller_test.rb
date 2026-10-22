require "test_helper"

class StatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(@user = users(:one))
    connection = @user.bank_connections.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
    @groceries = @user.transaction_categories.create!(name: "Groceries", kind: :expense)
    @today = Time.find_zone("Europe/Helsinki").today
  end

  def txn(amount, date)
    @account.bank_transactions.create!(entry_reference: SecureRandom.hex(4), occurred_on: date, amount: amount,
                                       currency: "EUR", transaction_category: @groceries)
  end

  test "requires signing in" do
    sign_out
    get stats_path
    assert_redirected_to new_session_path
  end

  test "shows only the signed-in user's data" do
    txn(-42.5, @today)
    loan = @user.loans.create!(name: "Mortgage", creditor: "Nordea")
    loan.balances.create!(on: @today, balance: 1000)
    @account.balances.create!(on: @today, booked: 500)

    sign_in_as(users(:two))
    get stats_path

    assert_response :success
    assert_select ".bar-row", 0
    assert_select "table.loans", 0
    assert_select "table.accounts", 0
  end

  test "defaults to this month" do
    txn(-42.5, @today)
    txn(-99, @today.prev_month.end_of_month)

    get stats_path

    assert_response :success
    assert_select ".chip-active", "This month"
    assert_select ".bar-row", 1
    assert_select ".bar-value", "42,50 €"
    assert_select "svg.pie path.pie-slice", 1
  end

  test "amounts can be shown in Danish kroner at today's ECB rate, remembered for the next page" do
    ExchangeRate.create!(currency: "DKK", on: Date.current, rate: "7.4600")
    txn(-10, @today)
    @account.balances.create!(on: @today, booked: 100)

    get stats_path(currency: "DKK")

    assert_response :success
    assert_select ".currency-filter .chip-active", "DKK"
    assert_select ".rate-note", /1 € = 7,4600 kr\./
    assert_select ".bar-value", "74,60 kr."
    assert_select "table.accounts td.number", text: "746,00 kr.", minimum: 1

    get stats_path
    assert_select ".bar-value", "74,60 kr."

    get stats_path(currency: "EUR")
    assert_select ".bar-value", "10,00 €"
  end

  test "an unknown currency or one without a rate falls back to euros" do
    txn(-10, @today)

    get stats_path(currency: "XXX")
    assert_select ".bar-value", "10,00 €"

    get stats_path(currency: "DKK")
    assert_response :success
    assert_select ".currency-filter .chip-active", "EUR"
    assert_select ".bar-value", "10,00 €"
  end

  test "quick filter for this year" do
    txn(-10, @today.beginning_of_year)
    txn(-20, @today)

    get stats_path(period: "year")

    assert_select ".chip-active", "This year"
    assert_select ".bar-value", "30,00 €"
  end

  test "custom timeline" do
    txn(-10, Date.new(2026, 1, 15))
    txn(-20, Date.new(2026, 3, 1))

    get stats_path(from: "2026-01-01", to: "2026-02-28")

    assert_select ".period-filters .chip-active", 0
    assert_select ".bar-value", "10,00 €"
    assert_select "input[name=from][value='2026-01-01']"
  end

  test "pie folds the smallest categories into Other past eight" do
    9.times do |i|
      category = @user.transaction_categories.create!(name: "Category #{i}", kind: :expense)
      @account.bank_transactions.create!(entry_reference: "r#{i}", occurred_on: @today, amount: -(i + 1),
                                         currency: "EUR", transaction_category: category)
    end

    get stats_path

    assert_select ".bar-row", 9
    assert_select "svg.pie path.pie-slice", 8
    assert_select ".legend li", text: /Other\s+3,00 €/
  end

  test "month tabs for the past 12 months" do
    month = @today.beginning_of_month.months_ago(11)
    txn(-10, month)
    txn(-20, month.next_month)

    get stats_path(month: month.strftime("%Y-%m"))

    assert_select ".month-tab", 12
    assert_select ".month-tab:first-child", month.strftime("%b %y")
    assert_select ".month-tab:last-child", @today.strftime("%b %y")
    assert_select ".month-tab-active", month.strftime("%b %y")
    assert_select ".period-filters .chip-active", 0
    assert_select ".bar-value", "10,00 €"
  end

  test "the current month's tab is active by default" do
    get stats_path

    assert_select ".month-tab-active", @today.strftime("%b %y")
  end

  test "loans are listed below income and expenses" do
    loan = @user.loans.create!(name: "Mortgage", creditor: "Nordea")
    loan.balances.create!(on: @today.beginning_of_month - 1, balance: 250_000)
    loan.balances.create!(on: @today, balance: 249_200)

    get stats_path

    assert_select "table.loans tbody tr", 1
    assert_select "table.loans td", "249 200,00 €"
    assert_select "table.loans td", "−800,00 €"
  end

  test "loans table totals what was taken and paid" do
    loan = @user.loans.create!(name: "Car loan", creditor: "Nordea Rahoitus")
    @account.bank_transactions.create!(entry_reference: "taken", occurred_on: @today, amount: 12_000, currency: "EUR", loan:)
    @account.bank_transactions.create!(entry_reference: "paid", occurred_on: @today, amount: -250, currency: "EUR", loan:)

    get stats_path

    assert_select "table.loans tfoot td", "12 000,00 €"
    assert_select "table.loans tfoot td", "250,00 €"
    assert_select ".loans-summary", "Taken 12 000,00 € · Paid 250,00 €"
  end

  test "accounts and credit cards are shown with their balances" do
    @account.balances.create!(on: @today.beginning_of_month - 1, booked: 1000)
    @account.balances.create!(on: @today, booked: 1234.56)
    card = CreditCard.create!(bank_connection: @account.bank_connection, uid: "card", name: "Credit Card", currency: "EUR",
                              raw: { "credit_limit" => { "amount" => "5000" } })
    card.balances.create!(on: @today, booked: -2345.67)

    get stats_path

    assert_select "table.accounts tbody tr", 1
    assert_select "table.accounts td", "1 234,56 €"
    assert_select "table.accounts td", "+234,56 €"
    assert_select "table.loans tbody th", text: /Credit Card Nordea · limit 5 000,00 €/
    assert_select "table.loans td", "2 345,67 €"
  end
end
