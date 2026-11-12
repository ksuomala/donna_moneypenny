require "test_helper"

class Api::TransactionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @headers = api_headers(@user)
    connection = @user.bank_connections.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Current", currency: "EUR")
    @food = @user.transaction_categories.create!(name: "Food", kind: :expense)
    @groceries = @user.transaction_categories.create!(name: "Groceries", parent: @food, kind: :expense)
    @own = @user.transaction_categories.create!(name: "Own", exclude_from_stats: true)
    @cash = ManualAccount.create!(user: @user, name: "Cash", currency: "EUR")

    other = users(:two)
    other_connection = other.bank_connections.create!(session_id: "t", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @other_account = other_connection.bank_accounts.create!(uid: "acc-2", currency: "EUR")
  end

  def txn(account, on, amount, category = nil, **attributes)
    account.bank_transactions.create!(entry_reference: SecureRandom.hex(4), occurred_on: on, amount: amount, currency: "EUR", transaction_category: category, **attributes)
  end

  test "every transaction of the user's accounts in the range, oldest first, with its category" do
    shop = txn(@account, Date.new(2026, 10, 2), -23.4, @groceries, counterparty_name: "K-Market", reference_number: "12345")
    transfer = txn(@account, Date.new(2026, 10, 1), -100, @own)
    pending = txn(@account, Date.new(2026, 10, 3), -5, nil, status: :pending)
    wallet = txn(@cash, Date.new(2026, 10, 31), -4)
    txn(@account, Date.new(2026, 9, 30), -1)
    txn(@account, Date.new(2026, 11, 1), -1)
    txn(@other_account, Date.new(2026, 10, 2), -999)

    get api_transactions_path(from: "2026-10-01", to: "2026-10-31"), headers: @headers

    assert_response :success
    body = response.parsed_body
    assert_equal [ "2026-10-01", "2026-10-31" ], body.values_at("from", "to")
    assert_equal [ transfer.id, shop.id, pending.id, wallet.id ], body["transactions"].map { |t| t["id"] }

    row = body["transactions"].second
    assert_equal({ "id" => @groceries.id, "name" => "Groceries", "parent" => "Food", "kind" => "expense" }, row["category"])
    assert_equal [ "-23.4", "K-Market", "12345", "booked", "Current" ], row.values_at("amount", "counterparty", "reference", "status", "account")
    assert_equal "excluded", body["transactions"].first.dig("category", "kind")
    assert_equal "pending", body["transactions"].third["status"]
    assert_nil body["transactions"].third["category"]
  end

  test "the range is required and checked" do
    get api_transactions_path(to: "2026-10-31"), headers: @headers
    assert_response :bad_request

    get api_transactions_path(from: "2026-11-01", to: "2026-10-31"), headers: @headers
    assert_response :unprocessable_entity
  end
end
