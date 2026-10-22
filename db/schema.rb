# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_23_100000) do
  create_table "bank_account_balances", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "bank_account_id", null: false
    t.date "on", null: false
    t.decimal "booked", precision: 12, scale: 2, null: false
    t.string "booked_type"
    t.decimal "available", precision: 12, scale: 2
    t.string "available_type"
    t.decimal "source_booked", precision: 12, scale: 2
    t.decimal "source_available", precision: 12, scale: 2
    t.string "source_currency"
    t.json "raw"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bank_account_id", "on"], name: "index_bank_account_balances_on_bank_account_id_and_on", unique: true
    t.index ["bank_account_id"], name: "index_bank_account_balances_on_bank_account_id"
  end

  create_table "bank_accounts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "bank_connection_id", null: false
    t.string "uid", null: false
    t.string "iban"
    t.string "name"
    t.string "currency"
    t.json "raw"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "identification_hash"
    t.datetime "last_synced_at"
    t.string "type"
    t.index ["bank_connection_id"], name: "index_bank_accounts_on_bank_connection_id"
    t.index ["iban"], name: "index_bank_accounts_on_iban"
    t.index ["identification_hash"], name: "index_bank_accounts_on_identification_hash"
    t.index ["type"], name: "index_bank_accounts_on_type"
    t.index ["uid"], name: "index_bank_accounts_on_uid", unique: true
  end

  create_table "bank_connections", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "session_id", null: false
    t.string "aspsp_name", null: false
    t.string "aspsp_country", null: false
    t.datetime "valid_until", null: false
    t.integer "status", default: 0, null: false
    t.json "raw"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "enable_banking_app_id"
    t.index ["enable_banking_app_id"], name: "index_bank_connections_on_enable_banking_app_id"
    t.index ["session_id"], name: "index_bank_connections_on_session_id", unique: true
    t.index ["user_id"], name: "index_bank_connections_on_user_id"
  end

  create_table "bank_transactions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "bank_account_id", null: false
    t.string "entry_reference", null: false
    t.integer "status", default: 0, null: false
    t.date "occurred_on", null: false
    t.date "booking_date"
    t.date "transaction_date"
    t.date "value_date"
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.string "currency", null: false
    t.decimal "source_amount", precision: 12, scale: 2
    t.string "source_currency"
    t.string "counterparty_name"
    t.text "description"
    t.string "reference_number"
    t.string "merchant_category_code"
    t.json "raw"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "transaction_category_id"
    t.bigint "loan_id"
    t.bigint "categorization_rule_id"
    t.index ["bank_account_id", "entry_reference"], name: "index_bank_transactions_on_bank_account_id_and_entry_reference", unique: true
    t.index ["bank_account_id", "occurred_on"], name: "index_bank_transactions_on_bank_account_id_and_occurred_on"
    t.index ["bank_account_id"], name: "index_bank_transactions_on_bank_account_id"
    t.index ["categorization_rule_id"], name: "index_bank_transactions_on_categorization_rule_id"
    t.index ["loan_id"], name: "index_bank_transactions_on_loan_id"
    t.index ["transaction_category_id"], name: "index_bank_transactions_on_transaction_category_id"
  end

  create_table "categorization_decisions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "categorization_run_id", null: false
    t.bigint "bank_transaction_id", null: false
    t.bigint "transaction_category_id"
    t.bigint "loan_id"
    t.integer "confidence", null: false
    t.string "reason"
    t.string "guard"
    t.boolean "applied", default: false, null: false
    t.datetime "created_at", null: false
    t.index ["bank_transaction_id"], name: "index_categorization_decisions_on_bank_transaction_id"
    t.index ["categorization_run_id", "bank_transaction_id"], name: "index_categorization_decisions_on_run_and_transaction", unique: true
    t.index ["categorization_run_id"], name: "index_categorization_decisions_on_categorization_run_id"
    t.index ["loan_id"], name: "index_categorization_decisions_on_loan_id"
    t.index ["transaction_category_id"], name: "index_categorization_decisions_on_transaction_category_id"
  end

  create_table "categorization_rules", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "transaction_category_id", null: false
    t.bigint "loan_id"
    t.string "reference"
    t.string "reference_prefix"
    t.bigint "bank_account_id"
    t.string "counterparty"
    t.decimal "amount", precision: 12, scale: 2
    t.integer "direction"
    t.integer "source", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.string "disabled_reason"
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["bank_account_id"], name: "index_categorization_rules_on_bank_account_id"
    t.index ["counterparty", "amount"], name: "index_categorization_rules_on_counterparty_and_amount"
    t.index ["loan_id"], name: "index_categorization_rules_on_loan_id"
    t.index ["reference"], name: "index_categorization_rules_on_reference"
    t.index ["reference_prefix"], name: "index_categorization_rules_on_reference_prefix"
    t.index ["transaction_category_id"], name: "index_categorization_rules_on_transaction_category_id"
    t.index ["user_id"], name: "index_categorization_rules_on_user_id"
  end

  create_table "categorization_runs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "mode", default: 0, null: false
    t.string "model", null: false
    t.string "prompt_version", null: false
    t.string "rules_digest", null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.integer "transactions_count", default: 0, null: false
    t.integer "confident_count", default: 0, null: false
    t.integer "unsure_count", default: 0, null: false
    t.integer "applied_count", default: 0, null: false
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.integer "cache_read_input_tokens", default: 0, null: false
    t.integer "cache_creation_input_tokens", default: 0, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_categorization_runs_on_user_id"
  end

  create_table "enable_banking_apps", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "application_id"
    t.text "private_key"
    t.string "callback_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["application_id"], name: "index_enable_banking_apps_on_application_id", unique: true
    t.index ["callback_token"], name: "index_enable_banking_apps_on_callback_token", unique: true
    t.index ["user_id"], name: "index_enable_banking_apps_on_user_id", unique: true
  end

  create_table "exchange_rates", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "currency", null: false
    t.date "on", null: false
    t.decimal "rate", precision: 16, scale: 6, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["currency", "on"], name: "index_exchange_rates_on_currency_and_on", unique: true
  end

  create_table "expenses", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "description", null: false
    t.integer "category", default: 0, null: false
    t.date "occurred_on", null: false
    t.string "merchant"
    t.integer "payment_method", default: 0, null: false
    t.text "notes"
    t.boolean "recurring", default: false, null: false
    t.string "currency", default: "USD", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["category"], name: "index_expenses_on_category"
    t.index ["occurred_on"], name: "index_expenses_on_occurred_on"
    t.index ["user_id"], name: "index_expenses_on_user_id"
  end

  create_table "households", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "incomes", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "description", null: false
    t.integer "source", default: 0, null: false
    t.date "received_on", null: false
    t.string "payer"
    t.integer "payment_method", default: 0, null: false
    t.text "notes"
    t.boolean "recurring", default: false, null: false
    t.string "currency", default: "USD", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["received_on"], name: "index_incomes_on_received_on"
    t.index ["source"], name: "index_incomes_on_source"
    t.index ["user_id"], name: "index_incomes_on_user_id"
  end

  create_table "loan_balances", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "loan_id", null: false
    t.date "on", null: false
    t.decimal "balance", precision: 12, scale: 2, null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["loan_id", "on"], name: "index_loan_balances_on_loan_id_and_on", unique: true
    t.index ["loan_id"], name: "index_loan_balances_on_loan_id"
  end

  create_table "loans", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "creditor", null: false
    t.text "description"
    t.string "currency", default: "EUR", null: false
    t.boolean "balance_from_transactions", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id", "name"], name: "index_loans_on_user_id_and_name", unique: true
  end

  create_table "sessions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "transaction_categories", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.integer "kind"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.bigint "parent_id"
    t.boolean "exclude_from_stats", default: false, null: false
    t.bigint "user_id"
    t.index ["parent_id"], name: "index_transaction_categories_on_parent_id"
    t.index ["user_id", "name"], name: "index_transaction_categories_on_user_id_and_name", unique: true
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "household_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["household_id"], name: "index_users_on_household_id"
  end

  add_foreign_key "bank_account_balances", "bank_accounts"
  add_foreign_key "bank_accounts", "bank_connections"
  add_foreign_key "bank_connections", "enable_banking_apps"
  add_foreign_key "bank_connections", "users"
  add_foreign_key "bank_transactions", "bank_accounts"
  add_foreign_key "bank_transactions", "categorization_rules", on_delete: :nullify
  add_foreign_key "bank_transactions", "loans"
  add_foreign_key "bank_transactions", "transaction_categories", on_delete: :nullify
  add_foreign_key "categorization_decisions", "bank_transactions", on_delete: :cascade
  add_foreign_key "categorization_decisions", "categorization_runs"
  add_foreign_key "categorization_decisions", "loans", on_delete: :nullify
  add_foreign_key "categorization_decisions", "transaction_categories", on_delete: :nullify
  add_foreign_key "categorization_rules", "bank_accounts"
  add_foreign_key "categorization_rules", "loans"
  add_foreign_key "categorization_rules", "transaction_categories"
  add_foreign_key "categorization_rules", "users"
  add_foreign_key "categorization_runs", "users"
  add_foreign_key "enable_banking_apps", "users"
  add_foreign_key "expenses", "users"
  add_foreign_key "incomes", "users"
  add_foreign_key "loan_balances", "loans"
  add_foreign_key "loans", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "transaction_categories", "transaction_categories", column: "parent_id"
  add_foreign_key "transaction_categories", "users"
  add_foreign_key "users", "households"
end
