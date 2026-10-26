# Sends the budget alerts that are due (Telegram::BudgetAlerts). Runs after the nightly
# categorizer, when the month's spending has settled; running it twice sends nothing twice.
class BudgetAlertsJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "budget_alerts"

  def perform
    sent = Telegram::BudgetAlerts.new.send!
    Rails.logger.info("[telegram] #{sent.size} budget alert(s) sent") if sent.any?
  end
end
