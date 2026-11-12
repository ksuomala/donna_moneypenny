require "test_helper"

class BankTransactions::NetWorthTest < ActiveSupport::TestCase
  test "subtracts loans and card debt once from bank and manual account assets" do
    user = users(:one)
    connection = user.bank_connections.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    account = connection.bank_accounts.create!(uid: "checking", currency: "EUR")
    account.balances.create!(on: Date.new(2026, 11, 1), booked: 1000)
    account.bank_transactions.create!(entry_reference: "spend", status: "booked", occurred_on: Date.new(2026, 11, 2), amount: -50, currency: "EUR")

    cash = ManualAccount.create!(user:, name: "Cash", currency: "EUR")
    cash.record_balance!(on: Date.new(2026, 11, 1), balance: 200)
    cash.record!(on: Date.new(2026, 11, 2), amount: -20)

    loan = user.loans.create!(name: "Mortgage", creditor: "Nordea")
    loan.balances.create!(on: Date.new(2026, 11, 1), balance: 400)
    card = CreditCard.create!(bank_connection: connection, uid: "card", currency: "EUR")
    card.balances.create!(on: Date.new(2026, 11, 1), booked: -100)

    result = BankTransactions::NetWorth.new(users: [ user ]).call

    assert_equal BigDecimal("1130"), result.assets
    assert_equal BigDecimal("500"), result.liabilities
    assert_equal BigDecimal("630"), result.amount
    assert_equal 0, result.unknown_balance_count
  end

  test "counts accounts without a known balance as excluded" do
    user = users(:one)
    user.bank_connections.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
      .bank_accounts.create!(uid: "checking", currency: "EUR")

    result = BankTransactions::NetWorth.new(users: [ user ]).call

    assert_equal BigDecimal("0"), result.amount
    assert_equal 1, result.unknown_balance_count
  end
end
