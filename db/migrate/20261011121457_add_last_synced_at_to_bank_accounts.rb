class AddLastSyncedAtToBankAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :bank_accounts, :last_synced_at, :datetime
  end
end
