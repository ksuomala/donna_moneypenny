require "test_helper"

class BankAccountBalanceTest < ActiveSupport::TestCase
  def balance(type, amount) = { "balance_type" => type, "balance_amount" => { "amount" => amount, "currency" => "EUR" } }

  test "maps the bank's booked and available balances, preferring the most current types" do
    attributes = BankAccountBalance.attributes_from_api([ balance("CLBD", "100.00"), balance("ITBD", "-2345.67"), balance("ITAV", "2654.33"), balance("CLAV", "1.00") ])

    assert_equal BigDecimal("-2345.67"), attributes[:booked]
    assert_equal "ITBD", attributes[:booked_type]
    assert_equal BigDecimal("2654.33"), attributes[:available]
    assert_equal "ITAV", attributes[:available_type]
    assert_equal 4, attributes[:raw].size
  end

  test "falls back to the closing booked balance and leaves available empty" do
    attributes = BankAccountBalance.attributes_from_api([ balance("CLBD", "100.00"), balance("OTHR", "5.00") ])

    assert_equal BigDecimal("100.00"), attributes[:booked]
    assert_equal "CLBD", attributes[:booked_type]
    assert_nil attributes[:available]
    assert_nil attributes[:available_type]
  end

  test "an available balance alone stands in for the booked one" do
    attributes = BankAccountBalance.attributes_from_api([ balance("ITAV", "100.00") ])

    assert_equal BigDecimal("100.00"), attributes[:booked]
    assert_equal BigDecimal("100.00"), attributes[:available]
    assert_equal %w[ITAV ITAV], attributes.values_at(:booked_type, :available_type)
  end

  test "is nothing without a booked or available balance" do
    assert_nil BankAccountBalance.attributes_from_api([ balance("OTHR", "100.00") ])
    assert_nil BankAccountBalance.attributes_from_api([])
  end

  test "one snapshot per account and day" do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    account = connection.bank_accounts.create!(uid: "acc-1")
    account.balances.create!(on: Date.new(2026, 10, 15), booked: 10)

    assert_raises(ActiveRecord::RecordInvalid) { account.balances.create!(on: Date.new(2026, 10, 15), booked: 20) }
  end
end
