class CreateTransactionCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :transaction_categories do |t|
      t.string :name, null: false
      t.integer :kind, null: false, default: 0

      t.timestamps
    end
    add_index :transaction_categories, :name, unique: true

    add_reference :bank_transactions, :transaction_category, foreign_key: { on_delete: :nullify }
  end
end
