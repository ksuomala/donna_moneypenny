class CreateBankTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_transactions do |t|
      t.references :bank_account, null: false, foreign_key: true
      t.string :entry_reference, null: false
      t.integer :status, null: false, default: 0
      t.date :occurred_on, null: false
      t.date :booking_date
      t.date :transaction_date
      t.date :value_date
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, null: false
      t.string :counterparty_name
      t.text :description
      t.string :reference_number
      t.string :merchant_category_code
      t.json :raw

      t.timestamps
    end
    add_index :bank_transactions, [ :bank_account_id, :entry_reference ], unique: true
    add_index :bank_transactions, [ :bank_account_id, :occurred_on ]
  end
end
