require "test_helper"

class BankTransactions::ConversionTest < ActiveSupport::TestCase
  setup do
    ExchangeRate.create!(currency: "DKK", on: Date.new(2026, 10, 1), rate: "7.46")
    ExchangeRate.create!(currency: "SEK", on: Date.new(2026, 10, 1), rate: "11.00")
    @conversion = BankTransactions::Conversion.new(client: Object.new)
  end

  test "euro rows pass through with empty source attributes" do
    rows = @conversion.transactions([ { amount: BigDecimal("-12.50"), currency: "EUR", occurred_on: Date.new(2026, 10, 1) } ])

    assert_equal [ { amount: BigDecimal("-12.50"), currency: "EUR", occurred_on: Date.new(2026, 10, 1), source_amount: nil, source_currency: nil } ], rows
  end

  test "other currencies become euros at the day's rate, keeping the bank's amount and currency" do
    rows = @conversion.transactions([
      { amount: BigDecimal("-746.00"), currency: "DKK", occurred_on: Date.new(2026, 10, 2) },
      { amount: BigDecimal("1100.00"), currency: "SEK", occurred_on: Date.new(2026, 10, 1) }
    ])

    assert_equal [ BigDecimal("-100.00"), BigDecimal("100.00") ], rows.map { |row| row[:amount] }
    assert_equal %w[EUR EUR], rows.map { |row| row[:currency] }
    assert_equal [ [ BigDecimal("-746.00"), "DKK" ], [ BigDecimal("1100.00"), "SEK" ] ], rows.map { |row| row.values_at(:source_amount, :source_currency) }
  end

  test "balances of an account in another currency are converted the same way" do
    attributes = @conversion.balance({ booked: BigDecimal("746.00"), available: BigDecimal("373.00"), booked_type: "ITAV" }, "DKK", Date.new(2026, 10, 3))

    assert_equal BigDecimal("100.00"), attributes[:booked]
    assert_equal BigDecimal("50.00"), attributes[:available]
    assert_equal [ BigDecimal("746.00"), BigDecimal("373.00"), "DKK" ], attributes.values_at(:source_booked, :source_available, :source_currency)
    assert_equal "ITAV", attributes[:booked_type]

    euros = @conversion.balance({ booked: BigDecimal("10.00"), available: nil }, "EUR", Date.new(2026, 10, 3))
    assert_equal [ BigDecimal("10.00"), nil, nil, nil, nil ], euros.values_at(:booked, :available, :source_booked, :source_available, :source_currency)
  end
end
