require "test_helper"

class ManualAccountTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @cash = ManualAccount.create!(user: @owner, name: "Cash", currency: "EUR")
    @groceries = @owner.transaction_categories.create!(name: "Groceries", kind: :expense)
  end

  test "has no connection and belongs to its user" do
    assert_nil @cash.bank_connection
    assert_match(/\Amanual-/, @cash.uid)
    assert_equal "manual account", @cash.kind
    assert_includes @owner.bank_accounts, @cash
    assert_includes BankAccount.owned_by(@owner), @cash
    assert_not ManualAccount.new(user: @owner, bank_connection: BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)).valid?
  end

  test "records a booked transaction in euros with a category" do
    transaction = @cash.record!(on: Date.new(2026, 11, 5), amount: BigDecimal("-12.50"), counterparty: "K-Market", description: "Market stall", category: @groceries)

    assert transaction.persisted?
    assert transaction.booked?
    assert_equal BigDecimal("-12.50"), transaction.amount
    assert_equal "EUR", transaction.currency
    assert_equal Date.new(2026, 11, 5), transaction.occurred_on
    assert_equal @groceries, transaction.transaction_category
    assert_includes @owner.bank_transactions, transaction
  end

  test "records without a category, leaving it for the categorizer" do
    transaction = @cash.record!(on: Date.new(2026, 11, 5), amount: -3, counterparty: "", description: nil)

    assert_nil transaction.transaction_category
    assert_nil transaction.counterparty_name
  end

  test "a dry run stores nothing" do
    assert_no_difference -> { BankTransaction.count } do
      @cash.record!(on: Date.new(2026, 11, 5), amount: -3, category: @groceries, dry_run: true)
    end
  end

  test "balance moves forward from the latest count by booked transactions on later dates" do
    @cash.record_balance!(on: Date.new(2026, 11, 1), balance: 100)
    @cash.record!(on: Date.new(2026, 11, 1), amount: -10, category: @groceries)
    @cash.record!(on: Date.new(2026, 11, 2), amount: -15, category: @groceries)

    assert_equal BigDecimal("85"), @cash.balance_on(Date.new(2026, 11, 3))
  end

  test "refuses another user's category and a parent category" do
    theirs = users(:two).transaction_categories.create!(name: "Groceries", kind: :expense)
    parent = @owner.transaction_categories.create!(name: "Investment", kind: :expense)
    @owner.transaction_categories.create!(name: "Funds", kind: :expense, parent: parent)

    assert_raises(ArgumentError) { @cash.record!(on: Date.current, amount: -3, category: theirs) }
    assert_raises(ActiveRecord::RecordInvalid) { @cash.record!(on: Date.current, amount: -3, category: parent) }
  end

  test "connected accounts take their connection's user" do
    connection = users(:two).bank_connections.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    account = connection.bank_accounts.create!(uid: "acc-1")

    assert_equal users(:two), account.user
  end
end
