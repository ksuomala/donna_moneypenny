require "test_helper"

class Api::ReportsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @headers = api_headers(@user)
    @account = account_for(@user, "acc-1")
    @groceries = @user.transaction_categories.create!(name: "Groceries", kind: :expense)
    @salary = @user.transaction_categories.create!(name: "Salary", kind: :income)

    @other = users(:two)
    @other_account = account_for(@other, "acc-2")
    @other_groceries = @other.transaction_categories.create!(name: "Groceries", kind: :expense)

    @today = Date.new(2026, 10, 21)
    @last_week = Date.new(2026, 10, 14)
  end

  def account_for(user, uid)
    connection = user.bank_connections.create!(session_id: uid, aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    connection.bank_accounts.create!(uid: uid, currency: "EUR")
  end

  def txn(account, amount, category, on: @last_week, **attributes)
    account.bank_transactions.create!(entry_reference: SecureRandom.hex(4), occurred_on: on, amount: amount, currency: "EUR", transaction_category: category, **attributes)
  end

  test "stats cover the range for the token's user only, with the budget prorated to it" do
    txn(@account, -120, @groceries)
    txn(@account, 2000, @salary)
    txn(@account, -50, @groceries, on: Date.new(2026, 10, 20))
    txn(@other_account, -999, @other_groceries)
    @user.budgets.create!(starts_on: Date.new(2026, 10, 1), monthly_total: 1000, lines_attributes: { "Groceries" => 400 })

    get api_stats_path(from: "2026-10-01", to: "2026-10-15"), headers: @headers

    assert_response :success
    body = response.parsed_body
    assert_equal [ "me", "2026-10-01", "2026-10-15" ], body.values_at("scope", "from", "to")
    assert_equal [ "2000.0", "120.0", "1880.0" ], body.values_at("income", "expenses", "net")
    assert_equal [ { "category" => "Salary", "kind" => "income", "amount" => "2000.0" } ], body["incomes"]
    assert_equal [ { "category" => "Groceries", "kind" => "expense", "amount" => "120.0" } ], body["spending"]
    assert_equal({ "name" => "Total", "budget" => "483.9", "spent" => "120.0", "left" => "363.9", "percent" => 25, "over" => false }, body.dig("budget", "total"))
  end

  test "stats need a valid range" do
    get api_stats_path(from: "2026-10-01"), headers: @headers
    assert_response :bad_request

    get api_stats_path(from: "2026-10-15", to: "2026-10-01"), headers: @headers
    assert_response :unprocessable_entity

    get api_stats_path(from: "last week", to: "2026-10-01"), headers: @headers
    assert_response :unprocessable_entity
  end

  test "the household scope combines the members, and needs a household" do
    get api_stats_path(scope: "household", from: "2026-10-12", to: "2026-10-18"), headers: @headers
    assert_response :not_found

    household = Household.create!(name: "Us")
    [ @user, @other ].each { |user| user.update!(household: household) }
    txn(@account, -120, @groceries)
    txn(@other_account, -30, @other_groceries)

    get api_stats_path(scope: "household", from: "2026-10-12", to: "2026-10-18"), headers: @headers
    assert_equal "household", response.parsed_body["scope"]
    assert_equal "150.0", response.parsed_body["expenses"]
  end

  test "the budget status shows the thresholds passed and the ones already reported" do
    budget = @user.budgets.create!(starts_on: Date.new(2026, 10, 1), monthly_total: 1000, lines_attributes: { "Groceries" => 400 })
    txn(@account, -550, @groceries, on: Date.new(2026, 10, 10))
    txn(@other_account, -900, @other_groceries, on: Date.new(2026, 10, 10))
    budget.alerts.create!(row_name: "Total", month: Date.new(2026, 10, 1), threshold: 50)

    travel_to(@today.in_time_zone("Europe/Helsinki").change(hour: 12)) { get api_budget_status_path, headers: @headers }

    assert_response :success
    body = response.parsed_body
    assert_equal "2026-10", body["month"]
    assert_equal [ 50, 100 ], body["thresholds"]
    assert_equal 55, body.dig("total", "percent")
    assert_equal [ 50 ], body["reached"]
    assert_equal [ 50 ], body["reported"]
    assert_equal [ { "name" => "Groceries", "budget" => "400.0", "spent" => "550.0", "left" => "-150.0", "percent" => 138, "over" => true } ], body["lines"]
  end

  test "the budget status without a budget this month" do
    get api_budget_status_path, headers: @headers

    assert_response :success
    assert_nil response.parsed_body["budget"]
  end

  test "uncategorized transactions are the user's booked ones with the categorizer's guess, and reading doesn't mark them" do
    first = txn(@account, -12.5, nil, counterparty_name: "K-Market", on: Date.new(2026, 10, 1))
    txn(@account, -40, nil, on: Date.new(2026, 10, 2))
    txn(@account, -5, nil, status: :pending)
    txn(@account, -7, @groceries)
    txn(@other_account, -8, nil)
    run = @user.categorization_runs.create!(mode: :apply, model: "test", prompt_version: "v1", rules_digest: "d", started_at: Time.current)
    run.decisions.create!(bank_transaction: first, transaction_category: @groceries, confidence: :unsure)

    get api_uncategorized_transactions_path(limit: 1), headers: @headers

    assert_response :success
    body = response.parsed_body
    assert_equal 2, body["total"]
    assert_equal [ first.id ], body["transactions"].map { |t| t["id"] }
    assert_equal({ "category_id" => @groceries.id, "name" => "Groceries" }, body["transactions"].first["guess"])
    assert_equal "K-Market", body["transactions"].first["counterparty"]
    assert_nil first.reload.uncategorized_notified_at
  end
end
