module Api
  # This month's budget against the spending so far, with the alert thresholds (50 and 100 % by
  # default) the total has passed and the ones Telegram::BudgetAlerts has already reported.
  class BudgetStatusesController < BaseController
    def show
      alerts = Telegram::BudgetAlerts.new
      status = alerts.status(owner)
      json = { scope: scope_name, month: alerts.month.begin.strftime("%Y-%m"), thresholds: alerts.thresholds }
      return render(json: json.merge(budget: nil)) unless status

      render json: json.merge(
        budget: { id: status.budget.id, starts_on: status.budget.starts_on, ends_on: status.budget.ends_on },
        total: budget_row_json(status.total),
        lines: status.report.rows.map { |row| budget_row_json(row) },
        reached: status.reached,
        reported: status.reported.sort
      )
    end
  end
end
