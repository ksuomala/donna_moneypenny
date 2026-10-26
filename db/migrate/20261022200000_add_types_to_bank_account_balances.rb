# Which of the bank's balance types the booked and available amounts came from, e.g. "ITBD" and
# "ITAV" on Nordea, or "ITAV" for both on Revolut, which reports no booked balance. Earlier
# snapshots get theirs from the stored response.
class AddTypesToBankAccountBalances < ActiveRecord::Migration[8.1]
  def up
    add_column :bank_account_balances, :booked_type, :string, after: :booked
    add_column :bank_account_balances, :available_type, :string, after: :available

    BankAccountBalance.reset_column_information
    BankAccountBalance.where.not(raw: nil).find_each do |snapshot|
      attributes = BankAccountBalance.attributes_from_api(snapshot.raw)
      snapshot.update_columns(attributes.slice(:booked_type, :available_type)) if attributes
    end
  end

  def down
    remove_column :bank_account_balances, :booked_type
    remove_column :bank_account_balances, :available_type
  end
end
