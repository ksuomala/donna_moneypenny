# The Telegram messages that follow a sync, once the categorizer has run on the new
# transactions: the weekly report for every user and household with a chat whose turn it is
# (Telegram::WeeklyReport.due?, once a week on the first sync of the week), then the budget
# alerts due (Telegram::BudgetAlerts, once per threshold and month). A failed send for one
# recipient doesn't stop the others; the job fails at the end so it shows in Solid Queue.
# Running it twice sends nothing twice.
class ReportsJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "reports"

  def perform
    failures = []
    client = Telegram::Client.for

    Telegram::Chats.owners.each do |owner|
      report = Telegram::WeeklyReport.new(owner)
      next unless report.due?

      report.send!(client: client)
      Rails.logger.info("[telegram] weekly report sent for #{Telegram::Chats.label(owner)}")
    rescue StandardError => e
      failures << "#{Telegram::Chats.label(owner)}: #{e.message}"
      Rails.logger.error("[telegram] weekly report for #{Telegram::Chats.label(owner)} failed: #{e.class}: #{e.message}")
    end

    begin
      sent = Telegram::BudgetAlerts.new.send!(client: client)
      Rails.logger.info("[telegram] #{sent.size} budget alert(s) sent") if sent.any?
    rescue StandardError => e
      failures << "budget alerts: #{e.message}"
      Rails.logger.error("[telegram] budget alerts failed: #{e.class}: #{e.message}")
    end

    raise Telegram::Client::Error, "Reports failed: #{failures.join('; ')}" if failures.any?
  end
end
