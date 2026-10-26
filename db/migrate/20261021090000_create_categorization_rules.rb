class CreateCategorizationRules < ActiveRecord::Migration[8.1]
  def change
    create_table :categorization_rules do |t|
      t.references :transaction_category, null: false, foreign_key: true
      t.references :loan, foreign_key: true
      t.string :reference
      t.string :reference_prefix
      t.references :bank_account, foreign_key: true
      t.string :counterparty
      t.decimal :amount, precision: 12, scale: 2
      t.integer :direction
      t.integer :source, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.string :disabled_reason
      t.string :note
      t.timestamps
    end
    add_index :categorization_rules, :reference
    add_index :categorization_rules, :reference_prefix
    add_index :categorization_rules, [ :counterparty, :amount ]

    add_reference :bank_transactions, :categorization_rule, foreign_key: { on_delete: :nullify }
  end
end
