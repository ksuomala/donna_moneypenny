require "test_helper"

class BankTransactions::BalanceRefreshTest < ActiveSupport::TestCase
  class Client
    def initialize(amount)
      @amount = amount
    end

    def balances(account_uid:)
      [ { "balance_type" => "ITBD", "balance_amount" => { "amount" => @amount, "currency" => "EUR" } } ]
    end
  end

  test "records the latest connected-account balance and skips manual accounts" do
    user = users(:one)
    connection = user.bank_connections.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    account = connection.bank_accounts.create!(uid: "checking", currency: "EUR")
    account.balances.create!(on: Time.find_zone("Europe/Helsinki").today, booked: 100)
    cash = ManualAccount.create!(user:, name: "Cash", currency: "EUR")
    client = Client.new("125.50")

    result = BankTransactions::BalanceRefresh.new(users: [ user ], client_factory: ->(_account) { client }).call

    assert_equal 1, result.updated
    assert_empty result.unavailable
    assert_equal 1, account.balances.count
    assert_equal BigDecimal("125.50"), account.balances.sole.booked
    assert_empty cash.balances
  end
end
