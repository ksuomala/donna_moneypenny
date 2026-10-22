require "net/http"

module ExchangeRates
  # The European Central Bank's daily reference rates, through the Frankfurter API
  # (https://frankfurter.dev): no key, one request for a whole range of days.
  class Client
    BASE_URL = "https://api.frankfurter.dev/v1/"

    Error = Class.new(StandardError)

    # Callers get their client through Client.for so tests can swap in a fake.
    class_attribute :factory, default: -> { new }

    def self.for = factory.call

    # Units of the currency per one euro on each day the ECB published a rate in from..to,
    # as { Date => BigDecimal }.
    def rates(currency:, from:, to:)
      uri = URI.join(BASE_URL, "#{from.iso8601}..#{to.iso8601}")
      uri.query = URI.encode_www_form(base: ExchangeRate::BASE, symbols: currency)

      response = Net::HTTP.get_response(uri)
      raise Error, "Exchange rate request for #{currency} failed (#{response.code}): #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).fetch("rates").to_h do |date, rates|
        [ Date.iso8601(date), BigDecimal(rates.fetch(currency).to_s) ]
      end
    rescue JSON::ParserError, KeyError => e
      raise Error, "Unexpected exchange rate response for #{currency}: #{e.message}"
    end
  end
end
