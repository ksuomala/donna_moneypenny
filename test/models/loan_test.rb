require "test_helper"

class LoanTest < ActiveSupport::TestCase
  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
  end

  def transaction(ref, on, amount, loan, status: "booked")
    @account.bank_transactions.create!(entry_reference: ref, status: status, occurred_on: Date.iso8601(on), amount: amount, currency: "EUR", loan: loan)
  end

  test "a bank loan's balance is the latest recorded one" do
    loan = Loan.create!(name: "Mortgage", creditor: "Nordea")
    loan.balances.create!(on: Date.new(2026, 4, 21), balance: 250_000)
    loan.balances.create!(on: Date.new(2026, 9, 30), balance: 246_000)
    transaction("p", "2026-06-02", -1200, loan)

    assert_nil loan.balance_on(Date.new(2026, 4, 20))
    assert_equal 250_000, loan.balance_on(Date.new(2026, 6, 30))
    assert_equal 246_000, loan.balance_on(Date.new(2026, 10, 1))
  end

  test "an interest-free loan's balance follows its booked transactions" do
    loan = Loan.create!(name: "Loan from a friend", creditor: "Friend", balance_from_transactions: true)
    loan.balances.create!(on: Date.new(2026, 3, 31), balance: 0)
    transaction("out", "2026-04-01", 20_000, loan)
    transaction("p1", "2026-05-15", -500, loan)
    transaction("p2", "2026-06-15", -500, loan)
    transaction("hold", "2026-06-20", -500, loan, status: "pending")

    assert_equal 0, loan.balance_on(Date.new(2026, 3, 31))
    assert_equal 20_000, loan.balance_on(Date.new(2026, 4, 30))
    assert_equal 19_000, loan.balance_on(Date.new(2026, 6, 30))
  end

  test "a recorded balance resets an interest-free loan's running total" do
    loan = Loan.create!(name: "Loan from family", creditor: "Family", balance_from_transactions: true)
    loan.balances.create!(on: Date.new(2026, 5, 10), balance: 0)
    transaction("a", "2026-05-11", 1_000, loan)
    loan.balances.create!(on: Date.new(2026, 5, 31), balance: 700)
    transaction("b", "2026-06-01", 1_000, loan)

    assert_equal 1_700, loan.balance_on(Date.new(2026, 6, 30))
  end

  test "deleting a loan unlinks its transactions" do
    loan = Loan.create!(name: "Car loan", creditor: "Bank")
    linked = transaction("a", "2026-09-02", 9_000, loan)

    loan.destroy

    assert_nil linked.reload.loan_id
  end
end
