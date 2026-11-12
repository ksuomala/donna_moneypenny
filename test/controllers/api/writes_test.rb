require "test_helper"

class Api::WritesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @headers = api_headers(@user)
    connection = @user.bank_connections.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", currency: "EUR")
    @groceries = @user.transaction_categories.create!(name: "Groceries", kind: :expense)

    @other = users(:two)
    other_connection = @other.bank_connections.create!(session_id: "t", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @other_account = other_connection.bank_accounts.create!(uid: "acc-2", currency: "EUR")
    @other_groceries = @other.transaction_categories.create!(name: "Groceries", kind: :expense)
  end

  def txn(account, amount, category = nil)
    account.bank_transactions.create!(entry_reference: SecureRandom.hex(4), occurred_on: Date.new(2026, 10, 10), amount: amount, currency: "EUR", transaction_category: category)
  end

  test "categorizing fills in the user's uncategorized transactions and skips the rest" do
    open = txn(@account, -10)
    done = txn(@account, -20, @groceries)
    theirs = txn(@other_account, -30)
    assignments = [ open, done, theirs ].map { |t| { transaction_id: t.id, category_id: @groceries.id } }

    post api_categorizations_path, params: { assignments: assignments }, headers: @headers, as: :json

    assert_response :success
    assert_equal [ { "transaction_id" => open.id, "category_id" => @groceries.id } ], response.parsed_body["applied"]
    assert_equal [ done.id, theirs.id ].sort, response.parsed_body["skipped"].sort
    assert_equal @groceries, open.reload.transaction_category
    assert_nil theirs.reload.transaction_category
  end

  test "categorizing with another user's category is refused and changes nothing" do
    open = txn(@account, -10)

    post api_categorizations_path, params: { assignments: [ { transaction_id: open.id, category_id: @other_groceries.id } ] }, headers: @headers, as: :json

    assert_response :unprocessable_entity
    assert_match(/Unknown or parent categories/, response.parsed_body["error"])
    assert_nil open.reload.transaction_category
  end

  test "a dry run of categorizing changes nothing" do
    open = txn(@account, -10)

    post api_categorizations_path, params: { assignments: [ { transaction_id: open.id, category_id: @groceries.id } ], dry_run: true }, headers: @headers, as: :json

    assert_equal 1, response.parsed_body["applied"].size
    assert_nil open.reload.transaction_category
  end

  test "categories are listed and created for the user, and a taken name is refused" do
    get api_categories_path, headers: @headers
    assert_equal [ "Groceries" ], response.parsed_body["categories"].map { |c| c["name"] }

    post api_categories_path, params: { name: "Food", kind: "expense", description: "Eating" }, headers: @headers, as: :json
    assert_response :created
    food = @user.transaction_categories.find_by!(name: "Food")
    assert_equal({ "id" => food.id, "name" => "Food", "kind" => "expense", "parent_id" => nil, "description" => "Eating", "assignable" => true }, response.parsed_body)

    post api_categories_path, params: { name: "Cafes", parent: "Food" }, headers: @headers, as: :json
    assert_response :created
    assert_equal food.id, response.parsed_body["parent_id"]

    post api_categories_path, params: { name: "Groceries", kind: "income" }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert @groceries.reload.expense?

    post api_categories_path, params: { name: "Odd", kind: "nonsense" }, headers: @headers, as: :json
    assert_response :unprocessable_entity
  end

  test "a category can't be put under another user's category" do
    @other.transaction_categories.create!(name: "Theirs", kind: :expense)

    post api_categories_path, params: { name: "Mine", parent: "Theirs" }, headers: @headers, as: :json

    assert_response :not_found
    assert_not TransactionCategory.exists?(name: "Mine")
  end

  test "accounts are the user's, and a created one is a manual account" do
    post api_accounts_path, params: { name: "Cash" }, headers: @headers, as: :json

    assert_response :created
    cash = ManualAccount.find(response.parsed_body["id"])
    assert_equal @user, cash.user
    assert_equal "manual account", response.parsed_body["kind"]

    get api_accounts_path, headers: @headers
    assert_equal [ @account.id, cash.id ], response.parsed_body["accounts"].map { |a| a["id"] }
  end

  test "a transaction goes on the user's manual account with the user's category" do
    cash = ManualAccount.create!(user: @user, name: "Cash", currency: "EUR")
    params = { account_id: cash.id, date: "2026-11-05", amount: "-12.50", counterparty: "K-Market", category_id: @groceries.id }

    assert_difference -> { cash.bank_transactions.count }, 1 do
      post api_transactions_path, params: params, headers: @headers, as: :json
    end
    assert_response :created
    transaction = cash.bank_transactions.sole
    assert_equal [ BigDecimal("-12.5"), @groceries, "K-Market", Date.new(2026, 11, 5) ],
                 [ transaction.amount, transaction.transaction_category, transaction.counterparty_name, transaction.occurred_on ]
  end

  test "transactions can't go on a bank account, another user's account or with another user's category" do
    cash = ManualAccount.create!(user: @user, name: "Cash", currency: "EUR")
    their_cash = ManualAccount.create!(user: @other, name: "Cash", currency: "EUR")

    [ { account_id: @account.id }, { account_id: their_cash.id }, { account_id: cash.id, category_id: @other_groceries.id } ].each do |params|
      post api_transactions_path, params: params.merge(date: "2026-11-05", amount: "-1"), headers: @headers, as: :json
      assert_response :not_found
    end
    post api_transactions_path, params: { account_id: cash.id, date: "yesterday", amount: "-1" }, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, BankTransaction.count
  end
end
