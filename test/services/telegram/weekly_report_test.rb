require "test_helper"

class Telegram::WeeklyReportTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(telegram_chat_id: "111")
    connection = BankConnection.create!(user: @user, session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", currency: "EUR")
    @groceries = TransactionCategory.create!(user: @user, name: "Groceries", kind: :expense)
    @salary = TransactionCategory.create!(user: @user, name: "Salary", kind: :income)
    @today = Date.new(2026, 10, 26) # a Monday
  end

  def txn(amount, category, date, account: @account)
    account.bank_transactions.create!(entry_reference: SecureRandom.hex(4), occurred_on: date, amount: amount, currency: "EUR", transaction_category: category)
  end

  test "last week's figures with the top expenses, and the month against the budget" do
    txn(3000, @salary, Date.new(2026, 10, 20))
    txn(-120.5, @groceries, Date.new(2026, 10, 22))
    txn(-400, @groceries, Date.new(2026, 10, 5))
    txn(-99, @groceries, Date.new(2026, 10, 26)) # this week: not in the week, in the month
    @user.budgets.create!(starts_on: Date.new(2026, 10, 1), monthly_total: 1000, lines_attributes: { "Groceries" => 500 })

    text = Telegram::WeeklyReport.new(@user, today: @today).text

    assert_equal Date.new(2026, 10, 19)..Date.new(2026, 10, 25), Telegram::WeeklyReport.new(@user, today: @today).week
    assert_includes text, "<b>Week 43: 19 Oct – 25 Oct 2026</b>"
    assert_includes text, "In 3 000,00 € · Out 120,50 € · Net +2 879,50 €"
    assert_includes text, "• Groceries 120,50 €"
    assert_includes text, "<b>Budget, October so far</b>"
    assert_includes text, "Total: 619,50 € of 1 000,00 € · 380,50 € left"
    assert_includes text, "⚠ Groceries: 619,50 € of 500,00 € · 119,50 € over"
  end

  test "without a budget only the week is reported, and it is sent to the user's chat" do
    text = nil
    TelegramStub.with do |stub|
      Telegram::WeeklyReport.new(@user, today: @today).send!
      text = stub.messages.sole.text
      assert_equal "111", stub.messages.sole.chat_id
    end

    assert_includes text, "In 0,00 € · Out 0,00 € · Net 0,00 €"
    assert_not_includes text, "Budget"
    assert_not_includes text, "Top spending"
  end

  test "a household's report combines the members and goes to the household's chat, or the members' without one" do
    other = users(:two)
    household = Household.create!(name: "Smiths", telegram_chat_id: "-500")
    [ @user, other ].each { |u| u.update!(household: household) }
    theirs = BankConnection.create!(user: other, session_id: "s2", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    their_account = theirs.bank_accounts.create!(uid: "acc-2", currency: "EUR")
    txn(-100, @groceries, Date.new(2026, 10, 21))
    txn(-50, TransactionCategory.create!(user: other, name: "Groceries", kind: :expense), Date.new(2026, 10, 21), account: their_account)
    household.budgets.create!(starts_on: Date.new(2026, 10, 1), monthly_total: 2000)

    report = Telegram::WeeklyReport.new(household, today: @today)
    assert_includes report.text, "<b>Smiths · Week 43"
    assert_includes report.text, "• Groceries 150,00 €"
    assert_includes report.text, "Total: 150,00 € of 2 000,00 €"
    TelegramStub.with { |stub| report.send!; assert_equal [ "-500" ], stub.messages.map(&:chat_id) }

    household.update!(telegram_chat_id: nil)
    other.update!(telegram_chat_id: "222")
    assert_equal [ "111", "222" ], Telegram::Chats.for(household).sort
    assert_equal [ @user, other, household ].to_set, Telegram::Chats.owners.to_set
  end

  test "names are escaped for Telegram's HTML" do
    txn(-10, TransactionCategory.create!(user: @user, name: "Bits & Bobs", kind: :expense), Date.new(2026, 10, 21))

    assert_includes Telegram::WeeklyReport.new(@user, today: @today).text, "• Bits &amp; Bobs 10,00 €"
  end

  test "due once a week: when nothing was sent since Monday, and a send records the time" do
    monday = Date.new(2026, 10, 19)
    report = Telegram::WeeklyReport.new(@user, today: monday)
    assert report.due?

    @user.update!(weekly_report_sent_at: Time.find_zone("Europe/Helsinki").local(2026, 10, 18, 19, 5))
    assert report.due?, "last sent before this week's Monday"

    @user.update!(weekly_report_sent_at: Time.find_zone("Europe/Helsinki").local(2026, 10, 19, 19, 5))
    assert_not report.due?
    assert_not Telegram::WeeklyReport.new(@user, today: monday + 6).due?
    assert Telegram::WeeklyReport.new(@user, today: monday + 7).due?

    @user.update!(weekly_report_sent_at: nil, telegram_chat_id: "111")
    TelegramStub.with { report.send! }
    assert_in_delta Time.current, @user.reload.weekly_report_sent_at, 5

    @user.update!(weekly_report_sent_at: nil, telegram_chat_id: nil)
    TelegramStub.with { report.send! }
    assert_nil @user.reload.weekly_report_sent_at, "nothing sent, nothing recorded"
  end
end
