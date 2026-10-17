class CreateBankConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_connections do |t|
      t.string :session_id, null: false
      t.string :aspsp_name, null: false
      t.string :aspsp_country, null: false
      t.datetime :valid_until, null: false
      t.integer :status, null: false, default: 0
      t.json :raw

      t.timestamps
    end
    add_index :bank_connections, :session_id, unique: true
  end
end
