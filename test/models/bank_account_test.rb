require "test_helper"

class BankAccountTest < ActiveSupport::TestCase
  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
  end

  def transaction(ref, on, amount, status: "booked")
    @account.bank_transactions.create!(entry_reference: ref, status:, occurred_on: Date.iso8601(on), amount:, currency: "EUR")
  end

  test "the balance moves forward from the latest snapshot by the booked transactions since it" do
    @account.balances.create!(on: Date.new(2026, 10, 15), booked: 1234.56)
    transaction("same-day", "2026-10-15", -20)
    transaction("later", "2026-10-20", -50)
    transaction("hold", "2026-10-25", 100, status: "pending")

    assert_equal BigDecimal("1234.56"), @account.balance_on(Date.new(2026, 10, 15))
    assert_equal BigDecimal("1184.56"), @account.balance_on(Date.new(2026, 10, 31))
    travel_to Date.new(2026, 10, 31) do
      assert_equal BigDecimal("1184.56"), @account.balance
    end
  end

  test "the balance is unknown without a snapshot and before the first one" do
    transaction("a", "2026-10-05", -100)
    assert_nil @account.balance_on(Date.new(2026, 10, 31))

    @account.balances.create!(on: Date.new(2026, 10, 15), booked: 1234.56)

    assert_nil @account.balance_on(Date.new(2026, 10, 14))
    assert_nil @account.balance_on(Date.new(2026, 9, 30))
  end
end
