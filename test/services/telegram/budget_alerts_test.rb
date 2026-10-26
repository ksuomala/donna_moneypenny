require "test_helper"

class Telegram::BudgetAlertsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(telegram_chat_id: "111")
    connection = BankConnection.create!(user: @user, session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", currency: "EUR")
    @groceries = TransactionCategory.create!(user: @user, name: "Groceries", kind: :expense)
    @cafes = TransactionCategory.create!(user: @user, name: "Cafes", kind: :expense)
    @budget = @user.budgets.create!(starts_on: Date.new(2026, 10, 1), monthly_total: 1000, lines_attributes: { "Groceries" => 400, "Cafes" => 50 })
    @today = Date.new(2026, 10, 20)
  end

  def txn(amount, category, date = Date.new(2026, 10, 10))
    @account.bank_transactions.create!(entry_reference: SecureRandom.hex(4), occurred_on: date, amount: amount, currency: "EUR", transaction_category: category)
  end

  def alerts = Telegram::BudgetAlerts.new(today: @today, thresholds: [ 80, 100 ])

  test "a row past a threshold is reported once per month, each threshold on its own" do
    txn(-45, @cafes)

    TelegramStub.with do |stub|
      sent = alerts.send!
      assert_equal [ [ "Cafes", 80 ] ], sent.map { |a| [ a.row.name, a.threshold ] }
      assert_equal "111", stub.messages.sole.chat_id
      assert_equal "<b>Cafes at 90 % of its budget</b>\nCafes: 45,00 € of 50,00 € · 5,00 € left in October", stub.messages.sole.text

      assert_empty alerts.send!
      assert_equal 1, stub.messages.size

      txn(-10, @cafes)
      sent = alerts.send!
      assert_equal [ [ "Cafes", 100 ] ], sent.map { |a| [ a.row.name, a.threshold ] }
      assert_equal "<b>Cafes over budget</b>\nCafes: 55,00 € of 50,00 € · 5,00 € over in October", stub.messages.last.text
    end

    assert_equal [ [ "Cafes", Date.new(2026, 10, 1), 80 ], [ "Cafes", Date.new(2026, 10, 1), 100 ] ],
                 @budget.alerts.order(:threshold).map { |a| [ a.row_name, a.month, a.threshold ] }
  end

  test "the total counts too, and a jump past both thresholds reports both at once" do
    txn(-1200, @groceries)

    TelegramStub.with do |stub|
      sent = alerts.send!
      assert_equal [ [ "Total", 80 ], [ "Total", 100 ], [ "Groceries", 80 ], [ "Groceries", 100 ] ], sent.map { |a| [ a.row.name, a.threshold ] }
      assert_equal 4, stub.messages.size
    end
  end

  test "nothing is due below the thresholds, for an owner without a chat, or outside the budget's months" do
    txn(-30, @cafes)
    assert_empty alerts.due

    txn(-30, @cafes)
    @user.update!(telegram_chat_id: nil)
    assert_empty alerts.due

    @user.update!(telegram_chat_id: "111")
    assert_equal 2, alerts.due.size
    assert_empty Telegram::BudgetAlerts.new(today: Date.new(2026, 9, 20), thresholds: [ 80, 100 ]).due
  end

  test "a failed send isn't recorded, so it is retried" do
    txn(-60, @cafes)

    TelegramStub.with(TelegramStub.new(raises: Telegram::Client::Error.new("down"))) do
      assert_raises(Telegram::Client::Error) { alerts.send! }
    end

    assert_empty @budget.alerts
    assert_equal 2, alerts.due.size
  end

  test "a household's budget goes to the household's chat with the household named" do
    other = users(:two)
    household = Household.create!(name: "Smiths", telegram_chat_id: "-500")
    [ @user, other ].each { |u| u.update!(household: household) }
    household.budgets.create!(starts_on: Date.new(2026, 10, 1), lines_attributes: { "Groceries" => 100 })
    txn(-100, @groceries)

    TelegramStub.with do |stub|
      alerts.send!
      household_messages = stub.messages.select { |m| m.chat_id == "-500" }
      assert_equal 2, household_messages.size # 80 and 100, spent exactly to the budget
      assert_equal [ "<b>Smiths · Groceries at 100 % of its budget</b>\nGroceries: 100,00 € of 100,00 € · 0,00 € left in October" ], household_messages.map(&:text).uniq
    end
  end
end
