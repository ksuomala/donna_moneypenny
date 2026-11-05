# Sends a user's uncategorized-transactions notice (Telegram::UncategorizedNotice) once the
# categorizer's run for that user is through. Without user_id, every user with categories.
class UncategorizedNoticeJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "uncategorized_notice"

  def perform(user_id: nil)
    users = user_id ? [ User.find(user_id) ] : User.categorizing.to_a
    users.each do |user|
      sent = Telegram::UncategorizedNotice.new(user).send!
      Rails.logger.info("[telegram] uncategorized notice sent for #{user.email_address}") if sent.any?
    end
  end
end
