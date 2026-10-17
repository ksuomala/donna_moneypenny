class CreateIncomes < ActiveRecord::Migration[8.1]
  def change
    create_table :incomes do |t|
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :description, null: false
      t.integer :source, null: false, default: 0
      t.date :received_on, null: false
      t.string :payer
      t.integer :payment_method, null: false, default: 0
      t.text :notes
      t.boolean :recurring, null: false, default: false
      t.string :currency, null: false, default: "USD"

      t.timestamps
    end

    add_index :incomes, :received_on
    add_index :incomes, :source
  end
end
