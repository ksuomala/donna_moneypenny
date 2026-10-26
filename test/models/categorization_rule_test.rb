require "test_helper"

class CategorizationRuleTest < ActiveSupport::TestCase
  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
    @other = connection.bank_accounts.create!(uid: "acc-2", name: "Vuokratili", currency: "EUR")
    @own = TransactionCategory.create!(name: "Own", exclude_from_stats: true)
    @investment = TransactionCategory.create!(name: "Investment", kind: :investment)
    TransactionCategory.create!(name: "Apartment A", kind: :investment, parent: @investment)
  end

  def transaction(account: @account, reference: nil, counterparty: "Card Issuer", amount: -100)
    account.bank_transactions.build(entry_reference: "x", occurred_on: Date.current, amount: amount, currency: "EUR",
                                    reference_number: reference, counterparty_name: counterparty)
  end

  test "a rule needs a reference, a prefix, or a counterparty with an amount, and a leaf category" do
    assert CategorizationRule.new(reference: "12345678", transaction_category: @own).valid?
    assert CategorizationRule.new(reference_prefix: "98765000", transaction_category: @own).valid?
    assert CategorizationRule.new(counterparty: "Tenant", amount: 500, transaction_category: @own).valid?
    assert_not CategorizationRule.new(counterparty: "Tenant", transaction_category: @own).valid?
    assert_not CategorizationRule.new(transaction_category: @own).valid?
    assert_not CategorizationRule.new(reference: "1", reference_prefix: "12345678", transaction_category: @own).valid?
    assert_not CategorizationRule.new(reference_prefix: "1612", transaction_category: @own).valid?
    assert_not CategorizationRule.new(reference: "12345678", transaction_category: @investment).valid?
  end

  test "references are compared without spaces and leading zeros" do
    rule = CategorizationRule.new(reference: "0000 5550 001234", transaction_category: @own)

    assert_equal "5550001234", rule.reference
    assert rule.matches?(transaction(reference: "00000000005550001234"))
    assert rule.matches?(transaction(reference: "5550 001234"))
    assert_not rule.matches?(transaction(reference: "55500012340"))
    assert_not rule.matches?(transaction(reference: nil))
  end

  test "every condition the rule sets must match" do
    prefix = CategorizationRule.new(reference_prefix: "98765000012345", bank_account: @account, direction: :outgoing, transaction_category: @own)
    assert prefix.matches?(transaction(reference: "98765000012345509193"))
    assert_not prefix.matches?(transaction(reference: "98765000012345509193", account: @other))
    assert_not prefix.matches?(transaction(reference: "98765000012345509193", amount: 100))
    assert_not prefix.matches?(transaction(reference: "91234000098765605155"))

    rent = CategorizationRule.new(counterparty: "tenant  name", amount: 579, transaction_category: @own)
    assert rent.matches?(transaction(counterparty: "TENANT NAME", amount: 579))
    assert_not rent.matches?(transaction(counterparty: "TENANT NAME", amount: 580))
    assert_not rent.matches?(transaction(counterparty: "Someone Else", amount: 579))
  end
end
