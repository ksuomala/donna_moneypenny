class CreateExpenses < ActiveRecord::Migration[8.1]
  def change
    create_table :expenses do |t|
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :description, null: false
      t.integer :category, null: false, default: 0
      t.date :occurred_on, null: false
      t.string :merchant
      t.integer :payment_method, null: false, default: 0
      t.text :notes
      t.boolean :recurring, null: false, default: false
      t.string :currency, null: false, default: "USD"

      t.timestamps
    end

    add_index :expenses, :occurred_on
    add_index :expenses, :category
  end
end
