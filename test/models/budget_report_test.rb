require "test_helper"

class BudgetReportTest < ActiveSupport::TestCase
  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", currency: "EUR")
    @groceries = TransactionCategory.create!(name: "Groceries", kind: :expense)
    @cafes = TransactionCategory.create!(name: "Cafes", kind: :expense)
    @budget = User.owner.budgets.create!(starts_on: Date.new(2026, 10, 1), monthly_total: 1000, lines_attributes: { "Groceries" => 400, "Cafes" => 50 })
  end

  def txn(amount, category, date)
    @account.bank_transactions.create!(entry_reference: SecureRandom.hex(4), occurred_on: date, amount: amount, currency: "EUR", transaction_category: category)
  end

  test "a month against its budget: total and lines with spent, left and over" do
    txn(-300, @groceries, Date.new(2026, 10, 3))
    txn(-80, @cafes, Date.new(2026, 10, 4))

    report = BudgetReport.for(@budget, BankTransactions::Stats.new(Date.new(2026, 10, 1).all_month, user: User.owner))

    assert_equal 1, report.months
    assert_not report.partial?
    assert_equal [ 1000, 380, 620 ], [ report.total.budget, report.total.spent, report.total.left ]
    cafes, groceries = report.rows
    assert_equal [ "Cafes", 50, 80, -30, true, 100 ], [ cafes.name, cafes.budget, cafes.spent, cafes.left, cafes.over?, cafes.used ]
    assert_equal [ "Groceries", 400, 300, 100, false, 75 ], [ groceries.name, groceries.budget, groceries.spent, groceries.left, groceries.over?, groceries.used ]
  end

  test "a longer period prorates the monthly amounts, and a budget starting mid-period covers its own part" do
    txn(-100, @groceries, Date.new(2026, 9, 20))
    txn(-300, @groceries, Date.new(2026, 10, 3))

    year = BudgetReport.for(@budget, BankTransactions::Stats.new(Date.new(2026, 9, 1)..Date.new(2026, 11, 30), user: User.owner))
    assert year.partial?
    assert_equal Date.new(2026, 10, 1)..Date.new(2026, 11, 30), year.range
    assert_equal 2, year.months
    assert_equal [ 2000, 300 ], [ year.total.budget, year.total.spent ]
    assert_equal [ 800, 300 ], [ year.rows.last.budget, year.rows.last.spent ]

    assert_nil BudgetReport.for(@budget, BankTransactions::Stats.new(Date.new(2026, 9, 1).all_month, user: User.owner))
    assert_nil BudgetReport.for(nil, BankTransactions::Stats.new(Date.new(2026, 10, 1).all_month, user: User.owner))
  end

  test "a budget without a total has only lines" do
    @budget.update!(monthly_total: nil)
    report = BudgetReport.for(@budget, BankTransactions::Stats.new(Date.new(2026, 10, 1).all_month, user: User.owner))

    assert_nil report.total
    assert_equal %w[Cafes Groceries], report.rows.map(&:name)
  end
end
