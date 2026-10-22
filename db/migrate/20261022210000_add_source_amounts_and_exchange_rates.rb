# Amounts are stored in euros. A transaction or balance the bank reported in another currency
# keeps what the bank said in source_*, converted at the European Central Bank's reference rate
# of its day (exchange_rates: units of the currency per euro).
class AddSourceAmountsAndExchangeRates < ActiveRecord::Migration[8.1]
  def change
    create_table :exchange_rates do |t|
      t.string :currency, null: false
      t.date :on, null: false
      t.decimal :rate, precision: 16, scale: 6, null: false
      t.timestamps
    end
    add_index :exchange_rates, %i[currency on], unique: true

    change_table :bank_transactions, bulk: true do |t|
      t.decimal :source_amount, precision: 12, scale: 2, after: :currency
      t.string :source_currency, after: :source_amount
    end

    change_table :bank_account_balances, bulk: true do |t|
      t.decimal :source_booked, precision: 12, scale: 2, after: :available_type
      t.decimal :source_available, precision: 12, scale: 2, after: :source_booked
      t.string :source_currency, after: :source_available
    end
  end
end
