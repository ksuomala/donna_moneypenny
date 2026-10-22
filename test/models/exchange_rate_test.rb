require "test_helper"

class ExchangeRateTest < ActiveSupport::TestCase
  # Serves canned ECB rates and records the requests made.
  class FakeClient
    attr_reader :requests

    def initialize(rates)
      @rates = rates
      @requests = []
    end

    def rates(currency:, from:, to:)
      @requests << [ currency, from, to ]
      @rates.select { |on, _| (from..to).cover?(on) }
    end
  end

  test "fetches the missing days once and reuses the stored rates" do
    client = FakeClient.new({ Date.new(2026, 10, 15) => BigDecimal("7.46"), Date.new(2026, 10, 16) => BigDecimal("7.47") })
    dates = [ Date.new(2026, 10, 16), Date.new(2026, 10, 15) ]

    rates = ExchangeRate.ensure!("DKK", dates, client: client)

    assert_equal({ Date.new(2026, 10, 15) => BigDecimal("7.46"), Date.new(2026, 10, 16) => BigDecimal("7.47") }, rates)
    assert_equal [ [ "DKK", Date.new(2026, 10, 8), Date.new(2026, 10, 16) ] ], client.requests
    assert_equal 2, ExchangeRate.where(currency: "DKK").count

    ExchangeRate.ensure!("DKK", dates, client: client)
    assert_equal 1, client.requests.size
  end

  test "a weekend or holiday takes the latest rate published within a week before it" do
    ExchangeRate.create!(currency: "DKK", on: Date.new(2026, 10, 16), rate: "7.47")
    client = FakeClient.new({})

    rates = ExchangeRate.ensure!("DKK", [ Date.new(2026, 10, 18) ], client: client)

    assert_equal BigDecimal("7.47"), rates[Date.new(2026, 10, 18)]
    assert_empty client.requests
  end

  test "a day with no rate published within a week before it is an error" do
    ExchangeRate.create!(currency: "DKK", on: Date.new(2026, 10, 1), rate: "7.47")

    error = assert_raises(ExchangeRate::Missing) { ExchangeRate.ensure!("DKK", [ Date.new(2026, 10, 18) ], client: FakeClient.new({})) }
    assert_match "No DKK rate for 2026-10-18", error.message
  end
end
