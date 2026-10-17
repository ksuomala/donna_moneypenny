require "test_helper"

class LegalControllerTest < ActionDispatch::IntegrationTest
  test "privacy policy is public" do
    get privacy_path
    assert_response :success
    assert_select "h1", "Privacy Policy"
  end

  test "terms of service are public" do
    get terms_path
    assert_response :success
    assert_select "h1", "Terms of Service"
  end
end
