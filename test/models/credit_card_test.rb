require "test_helper"

class CreditCardTest < ActiveSupport::TestCase
  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @card = CreditCard.create!(bank_connection: connection, uid: "card", name: "Credit Card", currency: "EUR",
                               raw: { "cash_account_type" => "CARD", "credit_limit" => { "amount" => "5000", "currency" => "XXX" } })
  end

  test "what's owed is the booked balance with the sign flipped" do
    @card.balances.create!(on: Date.new(2026, 10, 15), booked: -2345.67, available: 2654.33)

    assert_nil @card.owed_on(Date.new(2026, 10, 14))
    assert_equal BigDecimal("2345.67"), @card.owed_on(Date.new(2026, 10, 15))
    assert_equal BigDecimal("2345.67"), @card.owed_on(Date.new(2026, 12, 31))
    assert_equal BigDecimal("-2345.67"), @card.balance_on(Date.new(2026, 10, 15))
  end

  test "credit limit and creditor come from the bank" do
    assert_equal 5_000, @card.credit_limit
    assert_equal "Nordea", @card.creditor
    assert @card.credit_card?
    assert_not @card.bank_connection.bank_accounts.create!(uid: "acc-1").credit_card?
  end

  test "is found as a bank account but not as a deposit account" do
    assert_instance_of CreditCard, BankAccount.find(@card.id)
    assert_empty BankAccount.deposit.where(id: @card.id)
  end
end
