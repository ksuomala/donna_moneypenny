require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "passwords are at least 12 characters" do
    assert_not User.new(email_address: "new@example.com", password: "short").valid?
    assert User.new(email_address: "new@example.com", password: "long enough password").valid?
  end

  test "the owner is the first user" do
    assert_equal User.order(:id).first, User.owner
  end

  test "claims the records that have no owner and leaves the others alone" do
    owner, other = users(:one), users(:two)
    unowned = TransactionCategory.create!(name: "Groceries", kind: :expense)
    unowned.update_column(:user_id, nil)
    theirs = other.transaction_categories.create!(name: "Groceries", kind: :expense)
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    connection.update_column(:user_id, nil)

    counts = owner.claim_unowned_records!

    assert_equal owner, unowned.reload.user
    assert_equal owner, connection.reload.user
    assert_equal other, theirs.reload.user
    assert_equal 1, counts["TransactionCategory"]
    assert_equal 1, counts["BankConnection"]
  end

  test "records created outside a request belong to the owner, sub-categories and rules to their category's user" do
    other = users(:two)
    parent = other.transaction_categories.create!(name: "Investment", kind: :investment)
    child = TransactionCategory.create!(name: "Apartment A", kind: :investment, parent: parent)
    rule = CategorizationRule.create!(transaction_category: child, reference: "12345")

    assert_equal User.owner, Loan.create!(name: "Car loan", creditor: "Bank").user
    assert_equal other, child.user
    assert_equal other, rule.user
  end

  test "category names are unique per user" do
    users(:one).transaction_categories.create!(name: "Groceries", kind: :expense)

    assert users(:two).transaction_categories.new(name: "Groceries", kind: :expense).valid?
    assert_not users(:one).transaction_categories.new(name: "Groceries", kind: :expense).valid?
  end
end
