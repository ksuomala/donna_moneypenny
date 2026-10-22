# One category's monthly amount in a budget, by category name.
class BudgetLine < ApplicationRecord
  belongs_to :budget

  validates :category_name, presence: true, uniqueness: { scope: :budget_id }
  validates :monthly_amount, numericality: { greater_than: 0 }
end
