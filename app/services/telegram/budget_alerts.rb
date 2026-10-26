module Telegram
  # Checks every budget in force this month against the month's spending and sends one message
  # when the total has passed a threshold (config.x.telegram.budget_thresholds, 50 and 100 % by
  # default) that hasn't been reported yet: each threshold is reported once per month
  # (BudgetAlert), and a jump past several at once reports only the highest. A budget without a
  # monthly total sends nothing. A user's budget goes to the user's chat, a household's to the
  # household's (Telegram::Chats). Sending and recording happen together, so a failed send is
  # retried the next time.
  class BudgetAlerts
    ROW = "Total".freeze

    Alert = Data.define(:budget, :row, :threshold, :month)

    attr_reader :today, :thresholds

    def initialize(today: Format.today, thresholds: Rails.configuration.x.telegram.budget_thresholds)
      @today = today
      @thresholds = thresholds
    end

    def month = today.all_month

    # The alerts due now, not yet sent: at most one per budget.
    def due
      owners = User.where(id: Budget.select(:user_id)).to_a + Household.where(id: Budget.select(:household_id)).to_a
      owners.filter_map do |owner|
        budget = Budget.applying_to(owner, month)
        next unless budget && Chats.for(owner).any?

        total = BudgetReport.for(budget, BankTransactions::Stats.new(month, users: Chats.members(owner)))&.total
        next unless total

        sent = budget.alerts.where(month: month.begin, row_name: ROW).pluck(:threshold)
        threshold = thresholds.select { |t| total.percent >= t }.max
        Alert.new(budget: budget, row: total, threshold: threshold, month: month.begin) if threshold && sent.exclude?(threshold)
      end
    end

    # Sends what is due and returns the alerts sent. The thresholds below the one reported are
    # recorded with it, so they are never reported afterwards.
    def send!(client: Client.for)
      due.each do |alert|
        BudgetAlert.transaction do
          thresholds.select { |t| t <= alert.threshold }.each do |t|
            alert.budget.alerts.find_or_create_by!(row_name: ROW, month: alert.month, threshold: t)
          end
          Chats.for(alert.budget.owner).each { |chat_id| client.send_message(chat_id: chat_id, text: text(alert)) }
        end
      end
    end

    def text(alert)
      row = alert.row
      title = row.over? ? "Over budget" : "Budget at #{row.percent} %"
      title = "#{alert.budget.household.name} · #{title}" if alert.budget.household
      [ Format.bold(title), "#{Format.budget_row(row)} in #{alert.month.strftime('%B')}" ].join("\n")
    end
  end
end
