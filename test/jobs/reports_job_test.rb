require "test_helper"

class ReportsJobTest < ActiveJob::TestCase
  setup do
    @one, @two = users(:one), users(:two)
    @one.update!(telegram_chat_id: "111")
    @two.update!(telegram_chat_id: "222")
  end

  test "sends the weekly report to everyone whose turn it is, once a week" do
    TelegramStub.with do |stub|
      ReportsJob.perform_now
      assert_equal [ "111", "222" ], stub.messages.map(&:chat_id).sort
      assert_in_delta Time.current, @one.reload.weekly_report_sent_at, 5

      ReportsJob.perform_now
      assert_equal 2, stub.messages.size, "sent again in the same week"

      @two.update!(weekly_report_sent_at: 8.days.ago)
      ReportsJob.perform_now
      assert_equal [ "222" ], stub.messages.drop(2).map(&:chat_id)
    end
  end

  test "a failed send doesn't stop the others and fails the job at the end" do
    TelegramStub.with(TelegramStub.new(raises: Telegram::Client::Error.new("down"))) do
      error = assert_raises(Telegram::Client::Error) { ReportsJob.perform_now }
      assert_match "down", error.message
    end
    assert_nil @one.reload.weekly_report_sent_at
  end

  test "does nothing when nobody has a chat" do
    User.update_all(telegram_chat_id: nil)
    TelegramStub.with { |stub| ReportsJob.perform_now; assert_empty stub.messages }
  end

  test "follows the categorizer run, and the weekly report has no schedule of its own" do
    assert_not YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production").values.any? { |t| t["class"].to_s.include?("Report") }
    assert_includes File.read(Rails.root.join("app/jobs/categorize_transactions_job.rb")), "ReportsJob.perform_later"
  end
end
