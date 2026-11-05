# When a booked transaction left without a category was listed in the owner's Telegram notice
# (Telegram::UncategorizedNotice), so each one is listed once. The backlog at the time of the
# migration counts as listed: the first notice lists the new ones, not every old row.
class AddUncategorizedNotifiedAt < ActiveRecord::Migration[8.1]
  def up
    add_column :bank_transactions, :uncategorized_notified_at, :datetime
    execute <<~SQL
      UPDATE bank_transactions SET uncategorized_notified_at = CURRENT_TIMESTAMP
      WHERE transaction_category_id IS NULL AND status = 0
    SQL
  end

  def down
    remove_column :bank_transactions, :uncategorized_notified_at
  end
end
