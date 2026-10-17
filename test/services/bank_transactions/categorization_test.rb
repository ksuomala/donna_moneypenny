require "test_helper"

class BankTransactions::CategorizationTest < ActiveSupport::TestCase
  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
    @groceries = TransactionCategory.create!(name: "Groceries", kind: :expense, description: "Grocery chains")
    @investment = TransactionCategory.create!(name: "Investment", kind: :investment)
    @apartment = TransactionCategory.create!(name: "Apartment A", kind: :investment, parent: @investment)
  end

  def transaction(ref, status: "booked", counterparty: "K-Market", **attributes)
    @account.bank_transactions.create!(entry_reference: ref, status: status, occurred_on: Date.new(2026, 10, 1),
                                       amount: -12.5, currency: "EUR", counterparty_name: counterparty, **attributes)
  end

  test "context lists assignable categories and earlier decisions" do
    transaction("a", transaction_category: @groceries)

    context = BankTransactions::Categorization.context

    assert_includes context, "#{@groceries.id}\tGroceries\texpense\t\tGrocery chains"
    assert_includes context, "#{@apartment.id}\tApartment A\tinvestment\tInvestment"
    assert_not_includes context, "\tInvestment\tinvestment\t\t"
    assert_includes context, "K-Market\t#{@account.id}\tGroceries\t1"
  end

  test "uncategorized lists only booked transactions without a category" do
    open = transaction("a", description: "Card\npurchase")
    transaction("b", transaction_category: @groceries)
    transaction("c", status: "pending")

    output = BankTransactions::Categorization.uncategorized

    assert_includes output, "1 total"
    assert_includes output, "#{open.id}\t#{@account.id}\t2026-10-01\t-12.5\tEUR\tK-Market\tCard purchase"
    assert_equal 1, output.lines.count { |line| !line.start_with?("#") }
  end

  test "parse reads id pairs and rejects anything else" do
    assert_equal({ 1 => 2, 3 => 4 }, BankTransactions::Categorization.parse("1=2, 3=4"))
    assert_raises(ArgumentError) { BankTransactions::Categorization.parse("1=groceries") }
  end

  test "apply fills in missing categories only" do
    open = transaction("a")
    done = transaction("b", transaction_category: @apartment)
    held = transaction("c", status: "pending")

    result = BankTransactions::Categorization.apply({ open.id => @groceries.id, done.id => @groceries.id, held.id => @groceries.id })

    assert_equal({ open.id => @groceries.id }, result.applied)
    assert_equal [ done.id, held.id ], result.skipped
    assert_equal @groceries, open.reload.transaction_category
    assert_equal @apartment, done.reload.transaction_category
    assert_nil held.reload.transaction_category
  end

  test "dry run changes nothing" do
    open = transaction("a")

    result = BankTransactions::Categorization.apply({ open.id => @groceries.id }, dry_run: true)

    assert_equal({ open.id => @groceries.id }, result.applied)
    assert_nil open.reload.transaction_category
  end

  test "apply refuses parent and unknown categories" do
    open = transaction("a")

    assert_raises(ArgumentError) { BankTransactions::Categorization.apply({ open.id => @investment.id }) }
    assert_raises(ArgumentError) { BankTransactions::Categorization.apply({ open.id => 0 }) }
    assert_nil open.reload.transaction_category
  end

  test "link_loans fills in missing loans only" do
    loans = TransactionCategory.create!(name: "Loans", exclude_from_stats: true)
    mortgage = Loan.create!(name: "Mortgage", creditor: "Nordea")
    other = Loan.create!(name: "Other", creditor: "Nordea")
    open = transaction("a", transaction_category: loans)
    done = transaction("b", transaction_category: loans, loan: other)

    output = BankTransactions::Categorization.unlinked_loan_transactions
    assert_includes output, "unlinked loan transactions: 1"
    assert_includes output, "Other\t#{@account.id}\tK-Market\t1"

    assert_raises(ArgumentError) { BankTransactions::Categorization.link_loans({ open.id => 0 }) }
    assert_equal({ open.id => mortgage.id }, BankTransactions::Categorization.link_loans({ open.id => mortgage.id }, dry_run: true).applied)
    assert_nil open.reload.loan

    result = BankTransactions::Categorization.link_loans({ open.id => mortgage.id, done.id => mortgage.id })

    assert_equal [ done.id ], result.skipped
    assert_equal mortgage, open.reload.loan
    assert_equal other, done.reload.loan
  end

  test "unlinked loans leave out interest and fees on a credit card" do
    loans = TransactionCategory.create!(name: "Loans", exclude_from_stats: true)
    card = CreditCard.create!(bank_connection: @account.bank_connection, uid: "card", name: "Credit Card", currency: "EUR")
    interest = card.bank_transactions.create!(entry_reference: "i", occurred_on: Date.new(2026, 10, 1), amount: -5, currency: "EUR", transaction_category: loans)
    payment = transaction("p", transaction_category: loans)

    lines = BankTransactions::Categorization.unlinked_loan_transactions.lines

    assert_includes lines.first, "unlinked loan transactions: 1"
    assert lines.any? { |line| line.start_with?("#{payment.id}\t") }
    assert lines.none? { |line| line.start_with?("#{interest.id}\t") }
  end

  test "context tells credit cards from other accounts" do
    card = CreditCard.create!(bank_connection: @account.bank_connection, uid: "card", name: "Credit Card", currency: "EUR")

    context = BankTransactions::Categorization.context

    assert_includes context, "#{@account.id}\tKäyttötili\taccount"
    assert_includes context, "#{card.id}\tCredit Card\tcredit card"
  end
end
