# Accounts get an owner of their own, so a manual account (cash) can exist without a bank
# connection. Connected accounts take their connection's user.
class AddUserToBankAccounts < ActiveRecord::Migration[8.1]
  def up
    add_reference :bank_accounts, :user, foreign_key: true, after: :bank_connection_id
    execute <<~SQL
      UPDATE bank_accounts
      JOIN bank_connections ON bank_connections.id = bank_accounts.bank_connection_id
      SET bank_accounts.user_id = bank_connections.user_id
    SQL
    change_column_null :bank_accounts, :bank_connection_id, true
  end

  def down
    change_column_null :bank_accounts, :bank_connection_id, false
    remove_reference :bank_accounts, :user, foreign_key: true
  end
end
