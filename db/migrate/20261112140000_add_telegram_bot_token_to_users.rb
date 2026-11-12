class AddTelegramBotTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :telegram_bot_token, :text
  end
end
