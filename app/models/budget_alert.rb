# A budget alert that was sent: this row of the budget (the total or a category name) passed
# this threshold in this month, so it isn't reported again (Telegram::BudgetAlerts).
class BudgetAlert < ApplicationRecord
  belongs_to :budget

  validates :row_name, :month, :threshold, presence: true
  validates :threshold, uniqueness: { scope: %i[budget_id row_name month] }
end
