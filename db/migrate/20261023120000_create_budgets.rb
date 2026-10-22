# Monthly spending budgets for a user or a household: a total and per-category amounts, valid
# from a start date, optionally until an end date. Shown on the stats page against the spending
# of the period (BudgetReport).
class CreateBudgets < ActiveRecord::Migration[8.1]
  def change
    create_table :budgets do |t|
      t.references :user, foreign_key: true
      t.references :household, foreign_key: true
      t.date :starts_on, null: false
      t.date :ends_on
      t.decimal :monthly_total, precision: 12, scale: 2
      t.timestamps
    end

    create_table :budget_lines do |t|
      t.references :budget, null: false, foreign_key: true
      t.string :category_name, null: false
      t.decimal :monthly_amount, precision: 12, scale: 2, null: false
      t.timestamps
    end
    add_index :budget_lines, %i[budget_id category_name], unique: true
  end
end
