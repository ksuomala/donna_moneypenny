# The ECB reference rate of a currency on a day: units of the currency per one euro. Rates are
# fetched once (ExchangeRates::Client) and kept; the ECB publishes none on weekends and
# holidays, so a day takes the latest rate published up to a week before it.
class ExchangeRate < ApplicationRecord
  BASE = "EUR"
  # How far back a day may borrow its rate from.
  MAX_AGE = 7.days

  Missing = Class.new(StandardError)

  validates :currency, :on, :rate, presence: true
  validates :rate, numericality: { greater_than: 0 }

  # Makes sure every day in dates has a rate for the currency, fetching the missing stretch
  # from the ECB in one request. Returns the rates by day, dates not published included.
  def self.ensure!(currency, dates, client: ExchangeRates::Client.for)
    dates = dates.uniq.sort
    rates = lookup(currency, dates)
    missing = dates.reject { |date| rates[date] }
    return rates if missing.empty?

    fetched = client.rates(currency: currency, from: missing.first - MAX_AGE, to: missing.last)
    rows = fetched.map { |on, rate| { currency: currency, on: on, rate: rate } }
    # MySQL upserts on the unique (currency, on) index.
    upsert_all(rows, record_timestamps: true) if rows.any?

    lookup(currency, dates).tap do |all|
      still = dates.reject { |date| all[date] }
      raise Missing, "No #{currency} rate for #{still.first}#{" and #{still.size - 1} more day(s)" if still.size > 1}" if still.any?
    end
  end

  # The stored rate for each day: the latest one published within MAX_AGE before it.
  def self.lookup(currency, dates)
    published = where(currency: currency, on: (dates.min - MAX_AGE)..dates.max).order(:on).pluck(:on, :rate)

    dates.index_with do |date|
      on, rate = published.reverse_each.find { |published_on, _| published_on <= date }
      rate if on && on >= date - MAX_AGE
    end
  end
end
