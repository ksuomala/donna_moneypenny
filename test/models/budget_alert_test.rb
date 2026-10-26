require "test_helper"

class BudgetAlertTest < ActiveSupport::TestCase
  test "one record per budget row, month and threshold, gone with the budget" do
    budget = User.owner.budgets.create!(starts_on: Date.new(2026, 10, 1), monthly_total: 100)
    budget.alerts.create!(row_name: "Total", month: Date.new(2026, 10, 1), threshold: 80)

    assert_not budget.alerts.build(row_name: "Total", month: Date.new(2026, 10, 1), threshold: 80).valid?
    assert budget.alerts.build(row_name: "Total", month: Date.new(2026, 11, 1), threshold: 80).valid?

    budget.destroy!
    assert_empty BudgetAlert.all
  end
end
