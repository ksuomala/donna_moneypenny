class AddDescriptionToTransactionCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :transaction_categories, :description, :text
  end
end
