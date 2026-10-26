# When a user's or a household's weekly report was last sent (Telegram::WeeklyReport), so the
# reports job after each sync sends one a week, on the first sync of the week.
class AddWeeklyReportSentAt < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :weekly_report_sent_at, :datetime
    add_column :households, :weekly_report_sent_at, :datetime
  end
end
