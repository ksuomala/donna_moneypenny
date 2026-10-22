module BankTransactions
  # Turns amounts the bank reported in another currency into euros at the ECB rate of their
  # day, keeping the bank's figures in the source_* attributes. Euro amounts pass through
  # untouched, with the source_* attributes empty.
  class Conversion
    def initialize(client: ExchangeRates::Client.for)
      @client = client
    end

    # Transaction attribute hashes (BankTransaction.attributes_from_api): :amount and :currency
    # become euros, :source_amount and :source_currency hold what the bank said.
    def transactions(rows)
      rates = rates_for(rows.reject { |row| euros?(row[:currency]) }.map { |row| [ row[:currency], row[:occurred_on].to_date ] })

      rows.map do |row|
        next row.merge(source_amount: nil, source_currency: nil) if euros?(row[:currency])

        row.merge(amount: to_euros(row[:amount], rates.fetch([ row[:currency], row[:occurred_on].to_date ])),
                  currency: ExchangeRate::BASE, source_amount: row[:amount], source_currency: row[:currency])
      end
    end

    # Balance attributes (BankAccountBalance.attributes_from_api) reported in currency, as of the day on.
    def balance(attributes, currency, on)
      return attributes.merge(source_booked: nil, source_available: nil, source_currency: nil) if euros?(currency)

      rate = rates_for([ [ currency, on ] ]).fetch([ currency, on ])
      attributes.merge(booked: to_euros(attributes[:booked], rate), available: attributes[:available] && to_euros(attributes[:available], rate),
                       source_booked: attributes[:booked], source_available: attributes[:available], source_currency: currency)
    end

    private

    # { [currency, date] => rate } for every pair, one ECB request per currency at most.
    def rates_for(pairs)
      pairs.uniq.group_by(&:first).each_with_object({}) do |(currency, dated), rates|
        ExchangeRate.ensure!(currency, dated.map(&:last), client: @client).each { |on, rate| rates[[ currency, on ]] = rate }
      end
    end

    # An amount without a currency is taken as euros.
    def euros?(currency) = currency.nil? || currency == ExchangeRate::BASE

    def to_euros(amount, rate)
      (amount / rate).round(2)
    end
  end
end
