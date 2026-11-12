namespace :telegram do
  desc "Send a user's or a household's weekly report and budget alerts to a Telegram chat. EMAIL=... or HOUSEHOLD=name, " \
       "CHAT_ID=... (the chat's id with the bot; a group's is negative). Leave CHAT_ID empty to stop the messages"
  task link: :environment do
    owner = telegram_owner
    owner.update!(telegram_chat_id: ENV["CHAT_ID"].to_s.strip.presence)
    puts owner.telegram_chat_id ? "#{Telegram::Chats.label(owner)} gets its messages in chat #{owner.telegram_chat_id}" : "#{Telegram::Chats.label(owner)} gets no messages"
  end

  desc "Send a test message to a user's or a household's chat. EMAIL=... or HOUSEHOLD=name"
  task test: :environment do
    owner = telegram_owner
    recipients = Telegram::Chats.recipients(owner)
    abort "#{Telegram::Chats.label(owner)} has no chat (telegram:link)" if recipients.empty?
    recipients.each { |recipient| recipient.send_message("Donna Moneypenny here. Messages for #{Telegram::Format.escape(Telegram::Chats.label(owner))} arrive in this chat.") }
    puts "Sent to #{recipients.map(&:chat_id).join(", ")}"
  end

  desc "Send a user's messages with their own bot, e.g. the one their Hermes polls, instead of the default one. " \
       "EMAIL=... (asks for the bot token, or BOT_TOKEN=... without a terminal; an empty one goes back to the default bot)"
  task bot: :environment do
    user = User.find_by!(email_address: ENV.fetch("EMAIL").strip.downcase)
    token = ENV.key?("BOT_TOKEN") ? ENV["BOT_TOKEN"] : ($stdin.tty? ? $stdin.getpass("Bot token: ") : abort("No terminal to ask for the token: set BOT_TOKEN=..."))
    user.update!(telegram_bot_token: token)
    puts user.telegram_bot_token ? "#{user.email_address} gets its messages from its own bot" : "#{user.email_address} gets its messages from the default bot"
  end

  desc "The weekly report, as the reports job sends it after the first sync of the week. EMAIL=... or HOUSEHOLD=name for one, " \
       "otherwise everyone with a chat; DRY_RUN=1 prints it instead of sending (a real send counts as this week's)"
  task weekly_report: :environment do
    owners = ENV["EMAIL"] || ENV["HOUSEHOLD"] ? [ telegram_owner ] : Telegram::Chats.owners
    owners.each do |owner|
      report = Telegram::WeeklyReport.new(owner)
      if ENV["DRY_RUN"].present?
        puts "--- #{Telegram::Chats.label(owner)} -> #{Telegram::Chats.for(owner).join(", ").presence || "nobody"}", report.text, ""
      else
        report.send!
        puts "Sent for #{Telegram::Chats.label(owner)}"
      end
    end
  end

  desc "The budget alerts due now, as the reports job sends them after each sync. DRY_RUN=1 prints them instead of sending (and doesn't record them)"
  task budget_alerts: :environment do
    alerts = Telegram::BudgetAlerts.new
    if ENV["DRY_RUN"].present?
      due = alerts.due
      due.each { |alert| puts "--- #{Telegram::Chats.for(alert.budget.owner).join(", ")}", alerts.text(alert), "" }
      puts "#{due.size} alert(s) due"
    else
      puts "#{alerts.send!.size} alert(s) sent"
    end
  end

  desc "The notice of transactions still without a category, as it follows the categorizer's run. EMAIL=... for one user, " \
       "otherwise everyone with categories; DRY_RUN=1 prints it instead of sending (a real send marks them listed)"
  task uncategorized: :environment do
    users = ENV["EMAIL"] ? [ telegram_owner ] : User.categorizing.to_a
    users.each do |user|
      notice = Telegram::UncategorizedNotice.new(user)
      if ENV["DRY_RUN"].present?
        due = notice.due
        puts "--- #{user.email_address} -> #{Telegram::Chats.for(user).join(", ").presence || "nobody"}", (due.any? ? notice.text(due) : "nothing to list"), ""
      else
        puts "#{user.email_address}: #{notice.send!.any? ? "sent" : "nothing sent"}"
      end
    end
  end

  def telegram_owner
    if ENV["HOUSEHOLD"].present?
      Household.find_by!(name: ENV["HOUSEHOLD"].strip)
    else
      User.find_by!(email_address: ENV.fetch("EMAIL").strip.downcase)
    end
  end
end
