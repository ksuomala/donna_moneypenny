# Replaces the "transfer" kind with an explicit flag. Excluded categories (own transfers,
# credit card payments, the home purchase) have no kind, since they never show up in reports.
class AddExcludeFromStatsToTransactionCategories < ActiveRecord::Migration[8.1]
  TRANSFER = 2

  def up
    add_column :transaction_categories, :exclude_from_stats, :boolean, null: false, default: false
    change_column_null :transaction_categories, :kind, true
    change_column_default :transaction_categories, :kind, from: 0, to: nil
    execute "UPDATE transaction_categories SET exclude_from_stats = TRUE, kind = NULL WHERE kind = #{TRANSFER}"
  end

  def down
    execute "UPDATE transaction_categories SET kind = #{TRANSFER} WHERE kind IS NULL"
    change_column_default :transaction_categories, :kind, from: nil, to: 0
    change_column_null :transaction_categories, :kind, false
    remove_column :transaction_categories, :exclude_from_stats
  end
end
