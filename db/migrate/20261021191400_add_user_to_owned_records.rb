# Every top-level record gets an owner; accounts, transactions, balances and decisions belong to
# a user through their connection, run or loan. user_id stays nullable until the existing rows
# are assigned to the first user (bin/rails users:create); a later migration makes it NOT NULL.
class AddUserToOwnedRecords < ActiveRecord::Migration[8.1]
  TABLES = %i[bank_connections categorization_rules categorization_runs expenses incomes].freeze

  def change
    TABLES.each { |table| add_reference table, :user, foreign_key: true }

    # Names are unique per user; the composite index also serves lookups by user.
    %i[transaction_categories loans].each do |table|
      add_reference table, :user, foreign_key: true, index: false
      remove_index table, :name, unique: true
      add_index table, %i[user_id name], unique: true
    end
  end
end
