module Telegram
  # Checks every budget in force this month against the month's spending and sends a message
  # for each row (the total or a category) that has passed a threshold (config.x.telegram
  # .budget_thresholds, 80 and 100 % by default) and hasn't been reported yet: each threshold
  # is reported once per row and month (BudgetAlert). A user's budget goes to the user's chat,
  # a household's to the household's (Telegram::Chats). Sending and recording happen together,
  # so a failed send is retried the next time.
  class BudgetAlerts
    Alert = Data.define(:budget, :row, :threshold, :month)

    attr_reader :today, :thresholds

    def initialize(today: Format.today, thresholds: Rails.configuration.x.telegram.budget_thresholds)
      @today = today
      @thresholds = thresholds
    end

    def month = today.all_month

    # The alerts due now, not yet sent.
    def due
      owners = User.where(id: Budget.select(:user_id)).to_a + Household.where(id: Budget.select(:household_id)).to_a
      owners.flat_map do |owner|
        budget = Budget.applying_to(owner, month)
        next [] unless budget && Chats.for(owner).any?

        report = BudgetReport.for(budget, BankTransactions::Stats.new(month, users: Chats.members(owner)))
        next [] unless report

        sent = budget.alerts.where(month: month.begin).pluck(:row_name, :threshold).to_set
        ([ report.total ].compact + report.rows).flat_map do |row|
          thresholds.select { |t| row.percent >= t && !sent.include?([ row.name, t ]) }
            .map { |t| Alert.new(budget: budget, row: row, threshold: t, month: month.begin) }
        end
      end
    end

    # Sends what is due and returns the alerts sent.
    def send!(client: Client.for)
      due.each do |alert|
        BudgetAlert.transaction do
          alert.budget.alerts.create!(row_name: alert.row.name, month: alert.month, threshold: alert.threshold)
          Chats.for(alert.budget.owner).each { |chat_id| client.send_message(chat_id: chat_id, text: text(alert)) }
        end
      end
    end

    def text(alert)
      row = alert.row
      what = row.over? ? "over budget" : "at #{row.percent} % of its budget"
      title = "#{row.name} #{what}"
      title = "#{alert.budget.household.name} · #{title}" if alert.budget.household
      [ Format.bold(title), "#{Format.budget_row(row)} in #{alert.month.strftime('%B')}" ].join("\n")
    end
  end
end
