ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  def owner_auth
    login = Rails.application.credentials.basic_auth
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(login[:username], login[:password]) }
  end

  # Swaps EnableBanking::Client.build for the given fake for the duration of the block.
  def with_enable_banking_client(fake)
    original = EnableBanking::Client.factory
    EnableBanking::Client.factory = -> { fake }
    yield
  ensure
    EnableBanking::Client.factory = original
  end
end
