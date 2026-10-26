class CreateCategorizationRunsAndDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :categorization_runs do |t|
      t.integer :mode, null: false, default: 0
      t.string :model, null: false
      t.string :prompt_version, null: false
      t.string :rules_digest, null: false
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :transactions_count, null: false, default: 0
      t.integer :confident_count, null: false, default: 0
      t.integer :unsure_count, null: false, default: 0
      t.integer :applied_count, null: false, default: 0
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cache_read_input_tokens, null: false, default: 0
      t.integer :cache_creation_input_tokens, null: false, default: 0
      t.text :error
      t.timestamps
    end

    create_table :categorization_decisions do |t|
      t.references :categorization_run, null: false, foreign_key: true
      t.references :bank_transaction, null: false, foreign_key: { on_delete: :cascade }
      t.references :transaction_category, foreign_key: { on_delete: :nullify }
      t.references :loan, foreign_key: { on_delete: :nullify }
      t.integer :confidence, null: false
      t.string :reason
      t.string :guard
      t.boolean :applied, null: false, default: false
      t.datetime :created_at, null: false
    end
    add_index :categorization_decisions, [ :categorization_run_id, :bank_transaction_id ], unique: true, name: "index_categorization_decisions_on_run_and_transaction"
  end
end
