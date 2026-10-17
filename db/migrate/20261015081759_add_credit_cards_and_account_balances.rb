class AddCreditCardsAndAccountBalances < ActiveRecord::Migration[8.1]
  def up
    add_column :bank_accounts, :type, :string
    add_index :bank_accounts, :type

    create_table :bank_account_balances do |t|
      t.references :bank_account, null: false, foreign_key: true
      t.date :on, null: false
      t.decimal :booked, precision: 12, scale: 2, null: false
      t.decimal :available, precision: 12, scale: 2
      t.json :raw
      t.timestamps
    end
    add_index :bank_account_balances, [ :bank_account_id, :on ], unique: true

    # Accounts the bank reports as card accounts are credit cards.
    execute <<~SQL.squish
      UPDATE bank_accounts SET type = 'CreditCard'
      WHERE JSON_UNQUOTE(JSON_EXTRACT(raw, '$.cash_account_type')) = 'CARD'
    SQL
  end

  def down
    drop_table :bank_account_balances
    remove_index :bank_accounts, :type
    remove_column :bank_accounts, :type
  end
end
