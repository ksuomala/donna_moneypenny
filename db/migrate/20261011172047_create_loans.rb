class CreateLoans < ActiveRecord::Migration[8.1]
  def change
    create_table :loans do |t|
      t.string :name, null: false
      t.string :creditor, null: false
      t.text :description
      t.string :currency, null: false, default: "EUR"
      t.boolean :balance_from_transactions, null: false, default: false

      t.timestamps
    end
    add_index :loans, :name, unique: true

    create_table :loan_balances do |t|
      t.references :loan, null: false, foreign_key: true
      t.date :on, null: false
      t.decimal :balance, precision: 12, scale: 2, null: false
      t.string :note

      t.timestamps
    end
    add_index :loan_balances, [ :loan_id, :on ], unique: true

    add_reference :bank_transactions, :loan, foreign_key: true
  end
end
