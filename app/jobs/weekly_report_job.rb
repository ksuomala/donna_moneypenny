# Every Monday morning (config/recurring.yml) each user and household with a Telegram chat gets
# last week's figures and this month's budget (Telegram::WeeklyReport). A failed send for one
# doesn't stop the others; the job fails at the end so it shows in Solid Queue.
class WeeklyReportJob < ApplicationJob
  queue_as :default

  def perform
    failures = []
    client = Telegram::Client.for

    Telegram::Chats.owners.each do |owner|
      Telegram::WeeklyReport.new(owner).send!(client: client)
      Rails.logger.info("[telegram] weekly report sent for #{Telegram::Chats.label(owner)}")
    rescue StandardError => e
      failures << "#{Telegram::Chats.label(owner)}: #{e.message}"
      Rails.logger.error("[telegram] weekly report for #{Telegram::Chats.label(owner)} failed: #{e.class}: #{e.message}")
    end

    raise Telegram::Client::Error, "Weekly report failed for #{failures.size} recipient(s): #{failures.join('; ')}" if failures.any?
  end
end
