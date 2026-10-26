# Telegram notifications (Telegram::Client): a weekly report every Monday (WeeklyReportJob,
# config/recurring.yml) and a message when a budget row passes a threshold (BudgetAlertsJob,
# after the nightly categorizer). The bot token comes from the credentials (telegram:
# bot_token:) or TELEGRAM_BOT_TOKEN; users are linked to a chat with bin/rails telegram:link.
Rails.application.configure do
  # Share of a budget row's monthly amount at which an alert is sent, each once per month.
  config.x.telegram.budget_thresholds = ENV.fetch("BUDGET_ALERT_THRESHOLDS", "80,100").split(",").map { |t| Integer(t.strip) }.sort
end
