ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

# Tests never reach the ECB: a conversion of a non-euro amount needs a stubbed rates client.
class UnstubbedExchangeRates
  def rates(**) = raise("ExchangeRates::Client called without a stub client in a test")
end
ExchangeRates::Client.factory = -> { UnstubbedExchangeRates.new }

# Tests never reach a model provider: an unstubbed client raises instead of spending tokens.
[ BankTransactions::Categorizer::AnthropicBackend, BankTransactions::Categorizer::OpenaiBackend, BankTransactions::Categorizer::JevBackend ].each do |backend|
  backend.client_factory = -> { raise "#{backend.name} called without a stub client in a test" }
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActiveSupport::TestCase
  # One key for every test Enable Banking app: generating RSA keys is slow.
  ENABLE_BANKING_TEST_KEY = OpenSSL::PKey::RSA.new(2048).to_pem

  def create_enable_banking_app(user, application_id: "app-#{user.id}")
    user.create_enable_banking_app!(application_id: application_id, private_key: ENABLE_BANKING_TEST_KEY)
  end

  # Swaps the client EnableBanking::Client.for builds for the given fake for the duration of the
  # block. The fake learns which app it was built for, if it asks (app=).
  def with_enable_banking_client(fake)
    original = EnableBanking::Client.factory
    EnableBanking::Client.factory = ->(app) { fake.tap { fake.app = app if fake.respond_to?(:app=) } }
    yield
  ensure
    EnableBanking::Client.factory = original
  end
end
