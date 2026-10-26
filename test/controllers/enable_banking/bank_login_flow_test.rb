require "test_helper"
require_relative "fake_client"

class EnableBanking::BankLoginFlowTest < ActionDispatch::IntegrationTest
  SESSION_DATA = {
    "session_id" => "sess-1",
    "aspsp" => { "name" => "Nordea", "country" => "FI" },
    "access" => { "valid_until" => "2027-04-09T12:00:00+00:00" },
    "accounts" => [
      { "uid" => "acc-1", "account_id" => { "iban" => "FI2112345600000785" }, "name" => "Käyttötili", "currency" => "EUR" },
      { "uid" => "acc-2", "account_id" => { "iban" => "FI5542345670000081" }, "currency" => "EUR" }
    ]
  }.freeze

  setup do
    sign_in_as(@user = users(:one))
    @app = create_enable_banking_app(@user)
  end

  test "pages require signing in" do
    sign_out

    get root_path
    assert_redirected_to new_session_path

    post enable_banking_authorization_path, params: { bank: "nordea" }
    assert_redirected_to new_session_path

    get enable_banking_callback_path(@app.callback_token), params: { code: "x", state: "y" }
    assert_redirected_to new_session_path

    get enable_banking_app_path
    assert_redirected_to new_session_path
  end

  test "connect sends the user to the bank with a state and the longest consent" do
    fake = EnableBanking::FakeClient.new

    with_enable_banking_client(fake) do
      post enable_banking_authorization_path, params: { bank: "nordea" }
    end

    assert_redirected_to "https://bank.example/authorize?id=123"
    _, args = fake.calls.assoc(:start_authorization)
    assert_equal "Nordea", args[:aspsp_name]
    assert_equal "FI", args[:country]
    assert_equal "http://www.example.com/enable_banking/sessions/#{@app.callback_token}", args[:redirect_url]
    assert_equal @app, fake.app
    assert_equal session[:enable_banking_state], args[:state]
    assert_in_delta 180.days.from_now, args[:valid_until], 2.hours
  end

  test "connect offers every supported bank and sends the chosen one to Enable Banking" do
    get root_path
    assert_select "form[action=?] input[name=bank][value=nordea]", enable_banking_authorization_path
    assert_select "form[action=?] input[name=bank][value=revolut]", enable_banking_authorization_path
    assert_select "form[action=?] input[name=bank][value=danske]", enable_banking_authorization_path

    fake = EnableBanking::FakeClient.new

    with_enable_banking_client(fake) do
      post enable_banking_authorization_path, params: { bank: "revolut" }
    end

    assert_redirected_to "https://bank.example/authorize?id=123"
    _, args = fake.calls.assoc(:start_authorization)
    assert_equal "Revolut", args[:aspsp_name]
    assert_equal "LT", args[:country]
    assert_equal [ :aspsps, "LT" ], fake.calls.assoc(:aspsps)
  end

  test "connect refuses a bank that is not offered" do
    fake = EnableBanking::FakeClient.new

    with_enable_banking_client(fake) do
      post enable_banking_authorization_path, params: { bank: "monzo" }
      post enable_banking_authorization_path
    end

    assert_redirected_to root_path
    assert_equal "Unknown bank.", flash[:alert]
    assert_empty fake.calls
  end

  test "callback stores the connection and its accounts" do
    fake = EnableBanking::FakeClient.new(session_data: SESSION_DATA)

    with_enable_banking_client(fake) do
      post enable_banking_authorization_path, params: { bank: "nordea" }
      state = session[:enable_banking_state]

      assert_difference -> { BankConnection.count } => 1, -> { BankAccount.count } => 2 do
        get enable_banking_callback_path(@app.callback_token), params: { code: "the-code", state: state }
      end
    end

    assert_equal @app, fake.app

    assert_redirected_to root_path
    assert_equal [ :create_session, "the-code" ], fake.calls.assoc(:create_session)

    connection = BankConnection.last
    assert_equal "sess-1", connection.session_id
    assert_equal @user, connection.user
    assert_equal @app, connection.enable_banking_app
    assert connection.usable?
    assert_equal %w[FI2112345600000785 FI5542345670000081], connection.bank_accounts.order(:uid).pluck(:iban)

    follow_redirect!
    assert_select ".flash-notice", /Connected to Nordea: 2 account/
    assert_select "li", /Käyttötili/
  end

  test "callback rejects a missing or wrong state without calling the bank" do
    fake = EnableBanking::FakeClient.new(session_data: SESSION_DATA)

    with_enable_banking_client(fake) do
      post enable_banking_authorization_path, params: { bank: "nordea" }

      assert_no_difference -> { BankConnection.count } do
        get enable_banking_callback_path(@app.callback_token), params: { code: "the-code", state: "forged" }
      end
    end

    assert_redirected_to root_path
    assert_nil fake.calls.assoc(:create_session)
  end

  test "connect asks for the user's own Enable Banking application first" do
    @app.destroy!

    with_enable_banking_client(EnableBanking::FakeClient.new) do
      post enable_banking_authorization_path, params: { bank: "nordea" }
    end

    assert_redirected_to enable_banking_app_path
  end

  test "callback refuses another user's app" do
    theirs = create_enable_banking_app(users(:two))
    fake = EnableBanking::FakeClient.new(session_data: SESSION_DATA)

    with_enable_banking_client(fake) do
      post enable_banking_authorization_path, params: { bank: "nordea" }
      state = session[:enable_banking_state]

      assert_no_difference -> { BankConnection.count } do
        get enable_banking_callback_path(theirs.callback_token), params: { code: "the-code", state: state }
      end
    end

    assert_redirected_to root_path
    assert_match "not started with your Enable Banking application", flash[:alert]
    assert_nil fake.calls.assoc(:create_session)
  end

  test "callback reports a cancelled bank login" do
    get enable_banking_callback_path(@app.callback_token), params: { error: "access_denied", error_description: "User cancelled" }

    assert_redirected_to root_path
    assert_equal "Bank login was cancelled or failed: User cancelled", flash[:alert]
  end

  test "reconnecting moves accounts to the new connection by IBAN" do
    first = BankConnection.record_session!(SESSION_DATA)
    second = BankConnection.record_session!(SESSION_DATA.merge(
      "session_id" => "sess-2",
      "accounts" => [ { "uid" => "acc-1-new", "account_id" => { "iban" => "FI2112345600000785" }, "currency" => "EUR" } ]
    ))

    account = BankAccount.find_by!(iban: "FI2112345600000785")
    assert_equal second, account.bank_connection
    assert_equal "acc-1-new", account.uid
    assert_equal 1, first.bank_accounts.count
  end

  test "accounts without an IBAN (cards) are matched by identification hash on reconnect" do
    card = { "uid" => "card-1", "identification_hash" => "hash-card", "name" => "", "product" => "Credit Card", "currency" => "EUR" }
    BankConnection.record_session!(SESSION_DATA.merge("accounts" => [ card ]))
    second = BankConnection.record_session!(SESSION_DATA.merge("session_id" => "sess-2", "accounts" => [ card.merge("uid" => "card-2") ]))

    account = BankAccount.find_by!(identification_hash: "hash-card")
    assert_equal 1, BankAccount.where(identification_hash: "hash-card").count
    assert_equal second, account.bank_connection
    assert_equal "Credit Card", account.display_name
  end

  test "another user connecting the same account gets an account of their own" do
    mine = users(:one).bank_connections.record_session!(SESSION_DATA)
    theirs = users(:two).bank_connections.record_session!(SESSION_DATA.merge(
      "session_id" => "sess-2",
      "accounts" => [ { "uid" => "acc-1-two", "account_id" => { "iban" => "FI2112345600000785" }, "currency" => "EUR" } ]
    ))

    assert_equal users(:two), theirs.user
    assert_equal [ mine, theirs ], BankAccount.where(iban: "FI2112345600000785").order(:id).map(&:bank_connection)
  end

  test "the bank connections page lists only the signed-in user's connections" do
    users(:two).bank_connections.record_session!(SESSION_DATA)

    get root_path

    assert_select "p", "No banks connected yet."
  end

  test "account names use the product, not the holder name" do
    connection = BankConnection.record_session!(SESSION_DATA.merge("accounts" => [
      { "uid" => "acc-9", "account_id" => { "iban" => "FI1410093000123458" }, "name" => "DOE JANE", "product" => "Käyttötili", "currency" => "EUR" }
    ]))

    assert_equal "Käyttötili …3458", connection.bank_accounts.first.display_name
  end

  test "an Enable Banking error is shown instead of crashing" do
    fake = EnableBanking::FakeClient.new(error: EnableBanking::Client::Error.new("boom"))

    with_enable_banking_client(fake) do
      post enable_banking_authorization_path, params: { bank: "nordea" }
    end

    assert_redirected_to root_path
    assert_match "boom", flash[:alert]
  end
end
