require "test_helper"

class BankTransactions::RulesTest < ActiveSupport::TestCase
  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
    @other = connection.bank_accounts.create!(uid: "acc-2", name: "Vuokratili", currency: "EUR")
    @own = TransactionCategory.create!(name: "Own", exclude_from_stats: true)
    @loans = TransactionCategory.create!(name: "Loans", exclude_from_stats: true)
    @groceries = TransactionCategory.create!(name: "Groceries", kind: :expense)
    @card_loan = Loan.create!(name: "Card loan", creditor: "Bank")
    @n = 0
  end

  def transaction(reference: nil, counterparty: "Card Issuer", amount: -100, category: nil, loan: nil, account: @account, status: "booked")
    account.bank_transactions.create!(entry_reference: "e#{@n += 1}", status: status, occurred_on: Date.current, amount: amount, currency: "EUR",
                                      reference_number: reference, counterparty_name: counterparty, transaction_category: category, loan: loan)
  end

  test "derive! makes rules from references used consistently at least three times, keeping a single account" do
    3.times { transaction(reference: "5550001234", category: @own) }
    transaction(reference: "00005550001234", category: @own, amount: -250)
    3.times { transaction(reference: "777000111222", category: @loans, loan: @card_loan, counterparty: "Bank") }
    2.times { transaction(reference: "222222222", category: @own) }
    2.times { transaction(reference: "333333333", category: @own) }
    transaction(reference: "333333333", category: @groceries)
    3.times { transaction(reference: "1232", category: @own) }
    3.times { |i| transaction(reference: "444444444", category: @own, account: [ @account, @other ][i % 2]) }

    preview = BankTransactions::Rules.derive!(dry_run: true)
    assert_empty CategorizationRule.all

    rules = BankTransactions::Rules.derive!
    by_ref = rules.index_by(&:reference)
    assert_equal %w[444444444 5550001234 777000111222], by_ref.keys.sort
    assert_equal rules.map(&:describe).sort, preview.map(&:describe).sort
    assert_equal [ @own, nil, @account ], by_ref["5550001234"].then { |r| [ r.transaction_category, r.loan, r.bank_account ] }
    assert_equal [ @loans, @card_loan ], by_ref["777000111222"].then { |r| [ r.transaction_category, r.loan ] }
    assert_nil by_ref["444444444"].bank_account
    assert by_ref.values.all?(&:derived?)
    assert_empty BankTransactions::Rules.derive!
  end

  test "derive! makes rules from the same amount to the same counterparty, unless a reference rule covers them" do
    3.times { transaction(counterparty: "TENANT NAME", amount: 579, category: @groceries) }
    transaction(counterparty: "Tenant Name", amount: 600, category: @groceries)
    3.times { transaction(counterparty: "Mixed Person", amount: 20, category: @own) }
    transaction(counterparty: "Mixed Person", amount: 20, category: @groceries)
    3.times { transaction(counterparty: "Card Issuer", amount: -100, reference: "5550001234", category: @own) }

    rules = BankTransactions::Rules.derive!

    assert_equal [ [ "5550001234", nil, nil ], [ nil, "TENANT NAME", 579 ] ], rules.map { |r| [ r.reference, r.counterparty, r.amount&.to_i ] }.sort_by(&:to_s)
  end

  test "apply! fills in missing categories and loans from active rules, manual rules first, and records the rule" do
    derived = CategorizationRule.create!(reference: "777000111222", transaction_category: @loans, loan: @card_loan)
    manual = CategorizationRule.create!(reference: "777000111222", counterparty: "Special", transaction_category: @own, source: :manual)
    CategorizationRule.create!(reference: "999999999", transaction_category: @own, active: false)
    open = transaction(reference: "7770 00111222", counterparty: "Bank")
    special = transaction(reference: "777000111222", counterparty: "Special")
    done = transaction(reference: "777000111222", category: @groceries)
    held = transaction(reference: "777000111222", status: "pending")
    off = transaction(reference: "999999999")
    rent = transaction(counterparty: "Tenant", amount: 579)
    by_amount = CategorizationRule.create!(counterparty: "tenant", amount: 579, transaction_category: @groceries)

    preview = BankTransactions::Rules.apply!(dry_run: true)
    assert_equal({ derived => 1, manual => 1, by_amount => 1 }, preview.categorized)
    assert_nil open.reload.transaction_category

    result = BankTransactions::Rules.apply!
    assert_equal 1, result.linked
    assert_equal [ @loans, @card_loan, derived ], [ open.reload.transaction_category, open.loan, open.categorization_rule ]
    assert_equal [ @own, nil, manual ], [ special.reload.transaction_category, special.loan, special.categorization_rule ]
    assert_equal [ @groceries, by_amount ], [ rent.reload.transaction_category, rent.categorization_rule ]
    assert_equal [ @groceries, nil ], [ done.reload.transaction_category, done.categorization_rule ]
    assert_nil held.reload.transaction_category
    assert_nil off.reload.transaction_category
  end

  test "retire! switches off rules that a categorized transaction contradicts" do
    rule = CategorizationRule.create!(reference: "5550001234", transaction_category: @own)
    loan_rule = CategorizationRule.create!(reference: "777000111222", transaction_category: @loans, loan: @card_loan)
    fine = CategorizationRule.create!(reference: "555555555", transaction_category: @own)
    2.times { transaction(reference: "5550001234", category: @own) }
    odd = transaction(reference: "005550001234", category: @groceries)
    transaction(reference: "777000111222", category: @loans, loan: Loan.create!(name: "Other", creditor: "Bank"))
    transaction(reference: "555555555", category: @own)
    transaction(reference: "555555555")

    assert_equal [ 2, 1 ], BankTransactions::Rules.check(rule)
    assert_equal [ rule, loan_rule ], BankTransactions::Rules.retire!(dry_run: true)
    assert rule.reload.active?

    BankTransactions::Rules.retire!

    assert_not rule.reload.active?
    assert_match "e.g. #{odd.id}", rule.disabled_reason
    assert_not loan_rule.reload.active?
    assert fine.reload.active?
  end

  test "refresh! retires, derives and applies, so a derived rule fills in the rest of its reference at once" do
    3.times { transaction(reference: "5550001234", category: @own) }
    open = transaction(reference: "5550001234")

    result = BankTransactions::Rules.refresh!

    assert_equal [ 0, 1, 1 ], [ result[:retired].size, result[:derived].size, result[:applied].categorized.values.sum ]
    assert_equal @own, open.reload.transaction_category
  end
end
