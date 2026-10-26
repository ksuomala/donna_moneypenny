require "test_helper"

class TransactionCategoryTest < ActiveSupport::TestCase
  test "names are required and unique" do
    TransactionCategory.create!(name: "Groceries", kind: :expense)

    assert_not TransactionCategory.new(name: "", kind: :expense).valid?
    assert_not TransactionCategory.new(name: "Groceries", kind: :expense).valid?
  end

  test "categories excluded from stats have no kind, all others need one" do
    assert TransactionCategory.new(name: "Own", exclude_from_stats: true).valid?
    assert_not TransactionCategory.new(name: "Own", exclude_from_stats: true, kind: :expense).valid?
    assert_not TransactionCategory.new(name: "Groceries").valid?

    TransactionCategory.create!(name: "Own", exclude_from_stats: true)
    groceries = TransactionCategory.create!(name: "Groceries", kind: :expense)
    assert_equal [ groceries ], TransactionCategory.in_stats.to_a
  end

  test "deleting a category leaves its transactions uncategorized" do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
    category = TransactionCategory.create!(name: "Groceries", kind: :expense)
    transaction = account.bank_transactions.create!(entry_reference: "a", occurred_on: Date.current, amount: -12.5, currency: "EUR", transaction_category: category)

    category.destroy

    assert_nil transaction.reload.transaction_category
  end

  test "sub-categories are one level deep and share the parent's kind" do
    investment = TransactionCategory.create!(name: "Investment", kind: :investment)
    apartment = TransactionCategory.create!(name: "Apartment A", kind: :investment, parent: investment)

    assert_equal [ apartment ], investment.children.to_a
    assert_not TransactionCategory.new(name: "Kitchen", kind: :investment, parent: apartment).valid?
    assert_not TransactionCategory.new(name: "Apartment B", kind: :expense, parent: investment).valid?
  end

  test "transactions can't be put on a category that has sub-categories" do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
    investment = TransactionCategory.create!(name: "Investment", kind: :investment)
    apartment = TransactionCategory.create!(name: "Apartment A", kind: :investment, parent: investment)
    transaction = account.bank_transactions.build(entry_reference: "rent", occurred_on: Date.current, amount: 750, currency: "EUR")

    transaction.transaction_category = investment
    assert_not transaction.valid?

    transaction.transaction_category = apartment
    assert transaction.valid?
  end
  test "define! creates a category and later updates only what is given" do
    created = TransactionCategory.define!(name: "Pets", kind: "expense", description: "Vet, food")
    assert created.previously_new_record?
    assert created.expense?

    updated = TransactionCategory.define!(name: "Pets", description: "Vet, food, insurance")
    assert_equal created, updated
    assert_not updated.previously_new_record?
    assert_equal "Vet, food, insurance", updated.description
    assert updated.expense?
  end

  test "define! handles excluded categories and sub-categories that inherit the parent's kind" do
    own = TransactionCategory.define!(name: "Own", kind: "excluded", description: "Transfers")
    assert own.exclude_from_stats?
    assert_nil own.kind

    investment = TransactionCategory.define!(name: "Investment", kind: "investment")
    flat = TransactionCategory.define!(name: "Apartment A", parent: "Investment", description: "Rent and costs")
    assert_equal investment, flat.parent
    assert flat.investment?
    assert_raises(ArgumentError) { TransactionCategory.define!(name: "Odd", kind: "weird") }
    assert_raises(ActiveRecord::RecordNotFound) { TransactionCategory.define!(name: "Orphan", parent: "Missing") }
  end

  test "import! creates parents with their children and updates existing ones" do
    TransactionCategory.create!(name: "Groceries", kind: :expense, description: "old")

    categories = TransactionCategory.import!([
      { "name" => "Groceries", "kind" => "expense", "description" => "Supermarkets" },
      { "name" => "Investment", "kind" => "investment", "description" => "Per investment",
        "children" => [ { "name" => "Apartment A", "description" => "Rent" } ] }
    ])

    assert_equal [ "Groceries", "Investment", "Apartment A" ], categories.map(&:name)
    assert_equal "Supermarkets", TransactionCategory.find_by!(name: "Groceries").description
    assert_equal "Investment", TransactionCategory.find_by!(name: "Apartment A").parent.name
  end

  test "seeds add missing categories and never overwrite existing ones" do
    TransactionCategory.create!(name: "Groceries", kind: :expense, description: "Mine")

    Rails.application.load_seed

    assert_equal "Mine", TransactionCategory.find_by!(name: "Groceries").description
    assert TransactionCategory.find_by!(name: "Own").exclude_from_stats?
    assert TransactionCategory.find_by!(name: "Salary").income?
  end

  test "define! works on the user's own categories, so two users can have the same name" do
    other_user = User.where.not(id: User.owner.id).first
    mine = TransactionCategory.define!(name: "Groceries", kind: "expense", description: "Mine")
    theirs = TransactionCategory.define!(name: "Groceries", kind: "expense", description: "Theirs", user: other_user)

    assert_not_equal mine, theirs
    assert_equal [ User.owner, other_user ], [ mine.user, theirs.user ]
    assert_equal "Theirs", TransactionCategory.define!(name: "Groceries", user: other_user).description
    assert_equal "Mine", mine.reload.description

    Current.user = other_user
    assert_equal theirs, TransactionCategory.define!(name: "Groceries", description: "Updated")
    assert_equal "Updated", theirs.reload.description
  ensure
    Current.reset
  end
end
