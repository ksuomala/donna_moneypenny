class AddParentToTransactionCategories < ActiveRecord::Migration[8.1]
  def change
    add_reference :transaction_categories, :parent, foreign_key: { to_table: :transaction_categories }
  end
end
