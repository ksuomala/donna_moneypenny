require "test_helper"
require "fugit"

class SyncBankTransactionsJobTest < ActiveJob::TestCase
  class StubClient
    def initialize(failing_uids: [])
      @failing_uids = failing_uids
    end

    def transactions(account_uid:, date_from:, continuation_key: nil)
      raise EnableBanking::Client::Error, "rate limited" if @failing_uids.include?(account_uid)
      raise ActiveRecord::StatementInvalid, "db hiccup" if account_uid == "acc-db-error"

      { "transactions" => [ {
        "entry_reference" => "ref-#{account_uid}", "status" => "BOOK", "credit_debit_indicator" => "DBIT",
        "transaction_amount" => { "amount" => "5.00", "currency" => "EUR" }, "booking_date" => "2026-10-01"
      } ] }
    end

    def balances(account_uid:)
      [ { "balance_type" => "CLBD", "balance_amount" => { "amount" => "100.00", "currency" => "EUR" } } ]
    end
  end

  setup do
    @app = create_enable_banking_app(users(:one))
    @connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now, enable_banking_app: @app)
    @first = @connection.bank_accounts.create!(uid: "acc-1")
    @second = @connection.bank_accounts.create!(uid: "acc-2")
  end

  def with_client(client, &)
    with_enable_banking_client(client, &)
  end

  test "syncs every account of active connections" do
    with_client(StubClient.new) { SyncBankTransactionsJob.perform_now }

    assert_equal 1, @first.bank_transactions.count
    assert_equal 1, @second.bank_transactions.count
    assert_equal [ 100, 100 ], [ @first, @second ].map(&:balance)
  end

  test "each connection is read with the app it was made with" do
    theirs = create_enable_banking_app(users(:two))
    other = BankConnection.create!(user: users(:two), session_id: "s2", aspsp_name: "Nordea", aspsp_country: "FI",
      valid_until: 1.month.from_now, enable_banking_app: theirs)
    other.bank_accounts.create!(uid: "acc-3")
    apps = []
    original = EnableBanking::Client.factory
    EnableBanking::Client.factory = ->(app) { apps << app; StubClient.new }

    SyncBankTransactionsJob.perform_now

    assert_equal [ @app, @app, theirs ].sort_by(&:id), apps.sort_by(&:id)
  ensure
    EnableBanking::Client.factory = original
  end

  test "a connection without an app fails its accounts only" do
    @connection.update!(enable_banking_app: nil)
    other = BankConnection.create!(session_id: "s2", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now, enable_banking_app: @app)
    third = other.bank_accounts.create!(uid: "acc-3")

    original = EnableBanking::Client.factory
    # The real factory for the connection without an app, which has no credentials to sign with.
    EnableBanking::Client.factory = ->(app) { app ? StubClient.new : original.call(app) }

    error = assert_raises(EnableBanking::Client::Error) { SyncBankTransactionsJob.perform_now }

    assert_match "acc-1: Enable Banking credentials are not configured", error.message
    assert_equal 1, third.bank_transactions.count
  ensure
    EnableBanking::Client.factory = original
  end

  test "one failing account doesn't stop the others, but the job still fails" do
    error = assert_raises(EnableBanking::Client::Error) do
      with_client(StubClient.new(failing_uids: [ "acc-1" ])) { SyncBankTransactionsJob.perform_now }
    end

    assert_match "rate limited", error.message
    assert_equal 0, @first.bank_transactions.count
    assert_equal 1, @second.bank_transactions.count
  end

  test "a non-API error on one account doesn't stop the others" do
    @first.update!(uid: "acc-db-error")

    error = assert_raises(EnableBanking::Client::Error) do
      with_client(StubClient.new) { SyncBankTransactionsJob.perform_now }
    end

    assert_match "db hiccup", error.message
    assert_equal 1, @second.bank_transactions.count
  end

  test "rules categorize after the sync, before the categorizer" do
    own = TransactionCategory.create!(name: "Own", exclude_from_stats: true)
    CategorizationRule.create!(reference: "ref-acc-1", transaction_category: own)
    client = StubClient.new
    client.define_singleton_method(:transactions) do |account_uid:, **params|
      super(account_uid: account_uid, **params).tap { |page| page["transactions"].each { |t| t["reference_number"] = "ref-#{account_uid}" } }
    end

    with_client(client) { SyncBankTransactionsJob.perform_now }

    assert_equal own, @first.bank_transactions.sole.transaction_category
    assert_nil @second.bank_transactions.sole.transaction_category
  end

  test "the categorizer follows the sync, also when an account failed" do
    assert_enqueued_with(job: CategorizeTransactionsJob) do
      assert_raises(EnableBanking::Client::Error) do
        with_client(StubClient.new(failing_uids: [ "acc-1" ])) { SyncBankTransactionsJob.perform_now }
      end
    end
  end

  test "expired consent marks the connection expired without calling the bank" do
    @connection.update!(valid_until: 1.day.ago)

    with_client(StubClient.new(failing_uids: [ "acc-1", "acc-2" ])) { SyncBankTransactionsJob.perform_now }

    assert @connection.reload.expired?
  end

  test "is scheduled daily at 19:00 Helsinki time in production" do
    task = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "sync_bank_transactions")
    schedule = Fugit.parse(task["schedule"])

    assert_equal "SyncBankTransactionsJob", task["class"]
    assert_equal [ 19, 0 ], schedule.next_time(Time.utc(2026, 1, 15)).to_t.in_time_zone("Europe/Helsinki").then { |t| [ t.hour, t.min ] }
    assert_equal [ 19, 0 ], schedule.next_time(Time.utc(2026, 7, 15)).to_t.in_time_zone("Europe/Helsinki").then { |t| [ t.hour, t.min ] }
  end
end
