require "test_helper"

class EnableBanking::ClientTest < ActiveSupport::TestCase
  setup do
    @key = OpenSSL::PKey::RSA.new(2048)
    @client = EnableBanking::Client.new(application_id: "app-123", private_key: @key.to_pem)
  end

  test "signs a short-lived RS256 token keyed by the application id" do
    payload, header = JWT.decode(@client.send(:access_token), @key.public_key, true, algorithm: "RS256")

    assert_equal "app-123", header["kid"]
    assert_equal "enablebanking.com", payload["iss"]
    assert_equal "api.enablebanking.com", payload["aud"]
    assert_equal 3600, payload["exp"] - payload["iat"]
  end

  test "refuses to build without credentials" do
    assert_raises(EnableBanking::Client::Error) do
      EnableBanking::Client.new(application_id: nil, private_key: nil)
    end
  end

  test "balances asks for the account's balances" do
    paths = []
    client = Class.new(EnableBanking::Client) do
      define_method(:get) { |path, params = {}| paths << path; { "balances" => [ { "balance_type" => "CLBD" } ] } }
    end.new(application_id: "app-123", private_key: @key.to_pem)

    assert_equal [ { "balance_type" => "CLBD" } ], client.balances(account_uid: "acc-1")
    assert_equal [ "/accounts/acc-1/balances" ], paths
  end
end
