module Telegram
  # A weekly report for a user or a household: last week's income, expenses and net with the
  # largest expense categories, then this month so far against the budget in force, in the
  # same scope as the stats page shows them (a household's combined, payments between the
  # members left out).
  class WeeklyReport
    TOP_EXPENSES = 5

    attr_reader :owner, :today

    def initialize(owner, today: Format.today)
      @owner = owner
      @today = today
    end

    def week = today.prev_week.all_week
    def month = today.all_month

    def text
      [ week_section, budget_section ].compact.join("\n\n")
    end

    # Once a week: due when none has been sent since the start of this week (Monday), so the
    # first sync of the week sends it and a missed day is caught up the next. A newly linked
    # chat gets its first report at the next sync.
    def due?
      sent_at = owner.weekly_report_sent_at
      sent_at.nil? || sent_at.in_time_zone(Format::TIME_ZONE).to_date < today.beginning_of_week
    end

    # Sends to the owner's chats and records the send; returns the messages as Telegram
    # describes them.
    def send!(client: Client.for)
      Chats.for(owner).map { |chat_id| client.send_message(chat_id: chat_id, text: text) }.tap do |sent|
        owner.update!(weekly_report_sent_at: Time.current) if sent.any?
      end
    end

    private

    def stats(range) = BankTransactions::Stats.new(range, users: Chats.members(owner))

    def week_section
      stats = stats(week)
      title = "Week #{week.begin.cweek}: #{week.begin.strftime('%-d %b')} – #{week.end.strftime('%-d %b %Y')}"
      title = "#{owner.name} · #{title}" if owner.is_a?(Household)
      lines = [ Format.bold(title),
                "In #{Format.money(stats.income_total)} · Out #{Format.money(stats.expense_total)} · Net #{Format.signed_money(stats.net)}" ]
      top = stats.expenses.first(TOP_EXPENSES)
      lines << "" << "Top spending" if top.any?
      top.each { |slice| lines << "• #{Format.escape(slice.name)} #{Format.money(slice.amount)}" }
      lines.join("\n")
    end

    # nil without a budget in force this month.
    def budget_section
      report = BudgetReport.for(Budget.applying_to(owner, month), stats(month))
      return unless report

      rows = [ report.total ].compact + report.rows
      ([ Format.bold("Budget, #{month.begin.strftime('%B')} so far") ] + rows.map { |row| "#{row.over? ? "⚠ " : ""}#{Format.budget_row(row)}" }).join("\n")
    end
  end
end
