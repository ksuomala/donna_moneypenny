require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "only the digest is stored and the token authenticates its user, recording the use" do
    token = ApiToken.generate!(user: users(:one), name: "hermes")
    plain = token.token

    assert_match(/\Adonna_\w{40}\z/, plain)
    stored = ApiToken.find(token.id)
    assert_nil stored.token
    assert_equal ApiToken.digest(plain), stored.token_digest
    assert_nil stored.last_used_at

    assert_equal users(:one), ApiToken.authenticate(plain).user
    assert stored.reload.last_used_at
  end

  test "an unknown or empty token authenticates nobody" do
    ApiToken.generate!(user: users(:one), name: "hermes")

    assert_nil ApiToken.authenticate("donna_unknown")
    assert_nil ApiToken.authenticate(nil)
  end

  test "a name is unique per user" do
    ApiToken.generate!(user: users(:one), name: "hermes")

    assert_raises(ActiveRecord::RecordInvalid) { ApiToken.generate!(user: users(:one), name: "hermes") }
    assert ApiToken.generate!(user: users(:two), name: "hermes")
  end
end
