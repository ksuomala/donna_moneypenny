# Telegram notifications: the chat a user's or a household's weekly report and budget alerts go
# to, and a record of every budget alert sent so a threshold is reported once per budget row
# and month.
class AddTelegramNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :telegram_chat_id, :string
    add_column :households, :telegram_chat_id, :string

    create_table :budget_alerts do |t|
      t.references :budget, null: false, foreign_key: true
      t.string :row_name, null: false
      t.date :month, null: false
      t.integer :threshold, null: false
      t.timestamps
    end
    add_index :budget_alerts, %i[budget_id row_name month threshold], unique: true
  end
end
