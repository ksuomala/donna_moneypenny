require "test_helper"
require "fugit"

class WeeklyReportJobTest < ActiveJob::TestCase
  test "sends to everyone with a chat and fails at the end if one send failed" do
    users(:one).update!(telegram_chat_id: "111")
    users(:two).update!(telegram_chat_id: "222")

    TelegramStub.with { |stub| WeeklyReportJob.perform_now; assert_equal [ "111", "222" ], stub.messages.map(&:chat_id).sort }

    TelegramStub.with(TelegramStub.new(raises: Telegram::Client::Error.new("down"))) do
      error = assert_raises(Telegram::Client::Error) { WeeklyReportJob.perform_now }
      assert_match "2 recipient(s)", error.message
    end
  end

  test "does nothing when nobody has a chat" do
    TelegramStub.with { |stub| WeeklyReportJob.perform_now; assert_empty stub.messages }
  end

  test "is scheduled on Monday mornings Helsinki time in production" do
    task = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "weekly_report")
    schedule = Fugit.parse(task["schedule"])

    assert_equal "WeeklyReportJob", task["class"]
    next_run = schedule.next_time(Time.utc(2026, 1, 15)).to_t.in_time_zone("Europe/Helsinki")
    assert_equal [ 1, 8, 0 ], [ next_run.wday, next_run.hour, next_run.min ]
  end
end
