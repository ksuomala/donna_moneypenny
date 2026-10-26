require "test_helper"
require_relative "fake_client"

class EnableBanking::AppsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(@user = users(:one)) }

  test "the first visit creates the app, so its callback URL can be registered" do
    assert_difference -> { EnableBankingApp.count } => 1 do
      get enable_banking_app_path
    end

    app = @user.reload.enable_banking_app
    assert_not app.configured?
    assert_select "code.callback-url", "http://www.example.com/enable_banking/sessions/#{app.callback_token}"

    assert_no_difference -> { EnableBankingApp.count } do
      get enable_banking_app_path
    end
  end

  test "saves credentials that Enable Banking accepts, signed with them" do
    fake = EnableBanking::FakeClient.new

    with_enable_banking_client(fake) do
      patch enable_banking_app_path, params: { enable_banking_app: { application_id: " app-new ", private_key: ENABLE_BANKING_TEST_KEY } }
    end

    assert_redirected_to root_path
    app = @user.reload.enable_banking_app
    assert app.configured?
    assert_equal "app-new", app.application_id
    assert_equal "app-new", fake.app.application_id
    assert_not_includes EnableBankingApp.connection.select_value("SELECT private_key FROM enable_banking_apps WHERE id = #{app.id}"), "PRIVATE KEY"
  end

  test "takes the key from an uploaded .pem file" do
    file = Rack::Test::UploadedFile.new(StringIO.new(ENABLE_BANKING_TEST_KEY), "application/x-pem-file", original_filename: "app.pem")

    with_enable_banking_client(EnableBanking::FakeClient.new) do
      patch enable_banking_app_path, params: { enable_banking_app: { application_id: "app-new", private_key_file: file, private_key: "" } }
    end

    assert_redirected_to root_path
    assert_equal ENABLE_BANKING_TEST_KEY, @user.reload.enable_banking_app.private_key
  end

  test "rejects credentials that Enable Banking refuses" do
    fake = EnableBanking::FakeClient.new(aspsps_error: EnableBanking::Client::Error.new("401 unauthorized"))

    with_enable_banking_client(fake) do
      patch enable_banking_app_path, params: { enable_banking_app: { application_id: "app-new", private_key: ENABLE_BANKING_TEST_KEY } }
    end

    assert_response :unprocessable_entity
    assert_select ".flash-alert", /did not accept these credentials: 401 unauthorized/
    assert_not @user.reload.enable_banking_app.configured?
  end

  test "rejects a key that is not an RSA private key, without asking Enable Banking" do
    fake = EnableBanking::FakeClient.new

    with_enable_banking_client(fake) do
      patch enable_banking_app_path, params: { enable_banking_app: { application_id: "app-new", private_key: "not a key" } }
    end

    assert_response :unprocessable_entity
    assert_select ".flash-alert", /not a PEM-encoded RSA private key/
    assert_empty fake.calls
  end

  test "a blank key keeps the stored one" do
    app = create_enable_banking_app(@user, application_id: "app-old")

    with_enable_banking_client(EnableBanking::FakeClient.new) do
      patch enable_banking_app_path, params: { enable_banking_app: { application_id: "app-renamed", private_key: "" } }
    end

    assert_redirected_to root_path
    assert_equal [ "app-renamed", ENABLE_BANKING_TEST_KEY ], app.reload.values_at(:application_id, :private_key)
  end

  test "another user's application ID is refused" do
    create_enable_banking_app(users(:two), application_id: "app-taken")

    with_enable_banking_client(EnableBanking::FakeClient.new) do
      patch enable_banking_app_path, params: { enable_banking_app: { application_id: "app-taken", private_key: ENABLE_BANKING_TEST_KEY } }
    end

    assert_response :unprocessable_entity
    assert_select ".flash-alert", /Application ID has already been taken/
  end
end
