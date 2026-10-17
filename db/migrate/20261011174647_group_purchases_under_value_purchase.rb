# Groups the Home purchase and Car purchase categories under a new Value purchase category.
# Moving them keeps their transactions in place. Their final names and descriptions are
# owner data and are set outside this migration (db/seeds.rb or the production database).
class GroupPurchasesUnderValuePurchase < ActiveRecord::Migration[8.1]
  PURCHASES = [ "Home purchase", "Car purchase" ].freeze

  def up
    execute <<~SQL
      INSERT INTO transaction_categories (name, kind, exclude_from_stats, created_at, updated_at)
      SELECT 'Value purchase', NULL, TRUE, NOW(), NOW() FROM DUAL
      WHERE NOT EXISTS (SELECT 1 FROM transaction_categories WHERE name = 'Value purchase')
    SQL
    parent_id = select_value("SELECT id FROM transaction_categories WHERE name = 'Value purchase'")

    PURCHASES.each do |name|
      execute "UPDATE transaction_categories SET parent_id = #{parent_id} WHERE name = #{quote(name)}"
    end
  end

  def down
    parent_id = select_value("SELECT id FROM transaction_categories WHERE name = 'Value purchase'")
    execute "UPDATE transaction_categories SET parent_id = NULL WHERE parent_id = #{parent_id}" if parent_id
    execute "DELETE FROM transaction_categories WHERE name = 'Value purchase'"
  end
end
