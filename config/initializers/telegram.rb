# Telegram notifications (Telegram::Client), sent by ReportsJob after each sync once the
# categorizer has run: a weekly report on the first sync of the week, and a message when the
# month's spending passes a share of the budget's monthly total. The bot token comes from the
# credentials (telegram: bot_token:) or TELEGRAM_BOT_TOKEN; users are linked to a chat with
# bin/rails telegram:link.
Rails.application.configure do
  # Shares of the budget's monthly total at which an alert is sent, each once per month.
  config.x.telegram.budget_thresholds = ENV.fetch("BUDGET_ALERT_THRESHOLDS", "50,100").split(",").map { |t| Integer(t.strip) }.sort
end
