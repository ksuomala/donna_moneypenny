# Each user registers their own Enable Banking application and activates it in restricted mode
# with their own accounts. A connection is signed with the key of the app that created it.
class CreateEnableBankingApps < ActiveRecord::Migration[8.1]
  def change
    create_table :enable_banking_apps do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :application_id
      t.text :private_key
      # Part of the app's own callback path, so it is known before the app is registered.
      t.string :callback_token, null: false, index: { unique: true }
      t.timestamps
    end

    add_index :enable_banking_apps, :application_id, unique: true
    add_reference :bank_connections, :enable_banking_app, foreign_key: true
  end
end
