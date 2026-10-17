class AddIdentificationHashToBankAccounts < ActiveRecord::Migration[8.1]
  class MigrationBankAccount < ActiveRecord::Base
    self.table_name = "bank_accounts"
  end

  def up
    add_column :bank_accounts, :identification_hash, :string
    add_index :bank_accounts, :identification_hash

    MigrationBankAccount.reset_column_information
    MigrationBankAccount.find_each do |account|
      raw = account.raw || {}
      account.update_columns(identification_hash: raw["identification_hash"], name: raw["product"].presence || account.name)
    end
  end

  def down
    remove_column :bank_accounts, :identification_hash
  end
end
