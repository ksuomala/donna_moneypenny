require "test_helper"

class Api::AuthenticationTest < ActionDispatch::IntegrationTest
  test "requests without a token or with an unknown one are refused" do
    get api_categories_path
    assert_response :unauthorized
    assert_equal "Missing or unknown API token", response.parsed_body["error"]

    get api_categories_path, headers: { "Authorization" => "Bearer donna_unknown" }
    assert_response :unauthorized
  end

  test "a session cookie is not enough" do
    sign_in_as(users(:one))

    get api_categories_path
    assert_response :unauthorized
  end

  test "a revoked token stops working" do
    headers = api_headers(users(:one))
    get api_categories_path, headers: headers
    assert_response :success

    ApiToken.destroy_all
    get api_categories_path, headers: headers
    assert_response :unauthorized
  end
end
