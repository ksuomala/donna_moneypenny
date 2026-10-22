# The currency the stats page shows its amounts in. Amounts are stored in euros; another
# currency is a display conversion at the latest ECB rate, the same rate for every amount on
# the page, so the page stays consistent with itself.
class DisplayCurrency
  UNITS = { "EUR" => "€", "DKK" => "kr." }.freeze
  CODES = UNITS.keys.freeze

  attr_reader :code, :rate, :on

  # The display currency for a code, falling back to euros for anything else. A currency
  # whose rate can't be had (no ECB rate within a week, the ECB unreachable for any reason and
  # nothing stored) also falls back to euros, so the page still renders.
  def self.for(code)
    code = code.presence_in(CODES) || ExchangeRate::BASE
    return new(ExchangeRate::BASE) if code == ExchangeRate::BASE

    on = Date.current
    rate = ExchangeRate.ensure!(code, [ on ])[on]
    new(code, rate: rate, on: on)
  rescue StandardError => e
    Rails.logger.warn("[display currency] #{code}: #{e.message}; trying the latest stored rate")
    latest = ExchangeRate.where(currency: code).order(:on).last
    latest ? new(code, rate: latest.rate, on: latest.on) : new(ExchangeRate::BASE)
  end

  def initialize(code, rate: BigDecimal(1), on: nil)
    @code = code
    @rate = rate
    @on = on
  end

  def euros? = code == ExchangeRate::BASE
  def unit = UNITS.fetch(code)

  def convert(amount)
    euros? ? amount : (amount * rate).round(2)
  end
end
