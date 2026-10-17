require "test_helper"

class BankTransactions::StatsTest < ActiveSupport::TestCase
  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
    @groceries = TransactionCategory.create!(name: "Groceries", kind: :expense)
    @salary = TransactionCategory.create!(name: "Salary", kind: :income)
    @own = TransactionCategory.create!(name: "Own", exclude_from_stats: true)
    investment = TransactionCategory.create!(name: "Investment", kind: :investment)
    @flat = TransactionCategory.create!(name: "Apartment A", kind: :investment, parent: investment)
    @other_flat = TransactionCategory.create!(name: "Apartment B", kind: :investment, parent: investment)
    @range = Date.new(2026, 10, 1).all_month
  end

  def txn(amount, category, date: Date.new(2026, 10, 5), status: "booked")
    @account.bank_transactions.create!(entry_reference: SecureRandom.hex(4), status: status, occurred_on: date,
                                       amount: amount, currency: "EUR", transaction_category: category)
  end

  def stats = BankTransactions::Stats.new(@range)

  test "an investment's rent and costs net into one income" do
    txn(1000, @flat)
    txn(-280, @flat)
    txn(-100, @flat)

    assert_equal [ [ "Apartment A", 620 ] ], stats.incomes.map { [ it.name, it.amount ] }
    assert_empty stats.expenses
  end

  test "an investment that cost more than it brought in is an expense" do
    txn(500, @other_flat)
    txn(-800, @other_flat)

    assert_equal [ [ "Apartment B", 300 ] ], stats.expenses.map { [ it.name, it.amount ] }
    assert_empty stats.incomes
  end

  test "expenses are positive totals per category, net of refunds, largest first" do
    txn(-50, @groceries)
    txn(-30, @groceries)
    txn(10, @groceries)
    txn(-120, @flat)
    txn(3000, @salary)

    assert_equal [ [ "Apartment A", 120 ], [ "Groceries", 70 ] ], stats.expenses.map { [ it.name, it.amount ] }
    assert_equal [ [ "Salary", 3000 ] ], stats.incomes.map { [ it.name, it.amount ] }
    assert_equal 3000, stats.income_total
    assert_equal 190, stats.expense_total
    assert_equal 2810, stats.net
  end

  test "leaves out excluded categories, pending rows and other dates" do
    txn(-500, @own)
    txn(-40, @groceries, status: "pending")
    txn(-40, @groceries, date: Date.new(2026, 9, 30))

    assert_empty stats.expenses
    assert_empty stats.incomes
  end

  test "uncategorized money out is an expense and money in an income, not netted" do
    txn(-15, nil)
    txn(-5, nil)
    txn(100, nil)
    txn(-15, nil, status: "pending")

    assert_equal [ [ "Uncategorized", 20 ] ], stats.expenses.map { [ it.name, it.amount ] }
    assert_equal [ [ "Uncategorized", 100 ] ], stats.incomes.map { [ it.name, it.amount ] }
    assert stats.expenses.first.uncategorized?
  end

  test "loans show their balance at the end of the range, its change and the money that moved" do
    friend = Loan.create!(name: "Loan from a friend", creditor: "Friend", balance_from_transactions: true)
    friend.balances.create!(on: Date.new(2026, 3, 31), balance: 0)
    @account.bank_transactions.create!(entry_reference: "out", occurred_on: Date.new(2026, 4, 1), amount: 20_000, currency: "EUR", loan: friend)
    @account.bank_transactions.create!(entry_reference: "p", occurred_on: Date.new(2026, 10, 15), amount: -500, currency: "EUR", loan: friend)
    Loan.create!(name: "Credit line", creditor: "Nordea")
    paid_off = Loan.create!(name: "Personal loan", creditor: "Nordea")
    paid_off.balances.create!(on: Date.new(2026, 3, 12), balance: 0)

    rows = stats.loans

    assert_equal [ "Credit line", "Loan from a friend" ], rows.map(&:name)
    assert_equal [ nil, nil, 0, 0 ], rows.first.to_h.values_at(:balance, :change, :taken, :paid)
    assert_equal [ 19_500, -500, 0, 500 ], rows.last.to_h.values_at(:balance, :change, :taken, :paid)
    assert_equal 19_500, stats.loan_total
  end

  test "loans taken and paid are summed over all loans" do
    friend = Loan.create!(name: "Loan from a friend", creditor: "Friend", balance_from_transactions: true)
    car = Loan.create!(name: "Car loan", creditor: "Nordea Rahoitus")
    [ [ friend, 5_000 ], [ friend, -300 ], [ car, 12_000 ], [ car, -250 ], [ car, -250 ] ].each_with_index do |(loan, amount), i|
      @account.bank_transactions.create!(entry_reference: "l#{i}", occurred_on: Date.new(2026, 10, 2), amount:, currency: "EUR", loan:)
    end
    @account.bank_transactions.create!(entry_reference: "old", occurred_on: Date.new(2026, 9, 2), amount: -999, currency: "EUR", loan: car)

    assert_equal 17_000, stats.loans_taken
    assert_equal 800, stats.loans_paid
  end

  test "a credit card is listed with the loans: what's owed, its change once snapshots cover the range, no taken or paid" do
    card = CreditCard.create!(bank_connection: @account.bank_connection, uid: "card", name: "Credit Card", currency: "EUR",
                              raw: { "credit_limit" => { "amount" => "5000", "currency" => "XXX" } })
    card.balances.create!(on: Date.new(2026, 10, 15), booked: -2345.67, available: 2654.33)
    [ [ "buy", -100 ], [ "interest", -5 ], [ "pay", 296 ], [ "hold", -50, "pending" ], [ "later", -50, "booked", Date.new(2026, 10, 20) ],
      [ "old", -999, "booked", Date.new(2026, 9, 2) ] ].each do |ref, amount, status, date|
      card.bank_transactions.create!(entry_reference: ref, status: status || "booked", occurred_on: date || Date.new(2026, 10, 10), amount:, currency: "EUR")
    end
    Loan.create!(name: "Credit line", creditor: "Nordea")

    rows = stats.loans

    assert_equal [ "Credit line", "Credit Card" ], rows.map(&:name)
    assert_nil rows.first.limit
    # Owed on 31 Oct: 2 345.67 + 50 booked after the snapshot. No snapshot by 30 Sep, so no change.
    assert_equal [ "Nordea", BigDecimal("2395.67"), nil, 0, 0, 5_000 ],
                 rows.last.to_h.values_at(:creditor, :balance, :change, :taken, :paid, :limit)
    assert_equal BigDecimal("2395.67"), stats.loan_total
    assert_equal 0, stats.loans_taken
    assert_equal 0, stats.loans_paid
  end

  test "accounts list the balance the bank last reported by the end of the range and its change" do
    @account.balances.create!(on: Date.new(2026, 9, 30), booked: 1000)
    @account.balances.create!(on: Date.new(2026, 10, 10), booked: 1500)
    @account.balances.create!(on: Date.new(2026, 10, 20), booked: 1200)
    @account.balances.create!(on: Date.new(2026, 11, 1), booked: 50)
    @account.bank_connection.bank_accounts.create!(uid: "acc-2", name: "EtuTili", currency: "EUR")
    CreditCard.create!(bank_connection: @account.bank_connection, uid: "card", name: "Credit Card", currency: "EUR")

    rows = stats.accounts

    assert_equal [ [ "Käyttötili", 1200, 200 ], [ "EtuTili", nil, nil ] ], rows.map { [ it.name, it.balance, it.change ] }
    assert_equal 1200, stats.account_total
  end
end
