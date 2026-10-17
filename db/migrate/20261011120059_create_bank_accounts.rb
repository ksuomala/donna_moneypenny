class CreateBankAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_accounts do |t|
      t.references :bank_connection, null: false, foreign_key: true
      t.string :uid, null: false
      t.string :iban
      t.string :name
      t.string :currency
      t.json :raw

      t.timestamps
    end
    add_index :bank_accounts, :uid, unique: true
    add_index :bank_accounts, :iban
  end
end
