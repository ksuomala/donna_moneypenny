module ApiTestHelper
  def api_headers(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: "test-#{SecureRandom.hex(3)}").token}" }
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include ApiTestHelper
end
