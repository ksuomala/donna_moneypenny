require "test_helper"

class BankTransactions::SyncTest < ActiveSupport::TestCase
  # Serves pages of transactions and the account's balances, and records the requests made.
  class PagedClient
    NORDEA_CARD_BALANCES = [
      { "name" => "Available balance", "balance_amount" => { "currency" => "EUR", "amount" => "2654.33" }, "balance_type" => "ITAV" },
      { "name" => "Booked balance", "balance_amount" => { "currency" => "EUR", "amount" => "-2345.67" }, "balance_type" => "ITBD" }
    ].freeze

    attr_reader :requests, :balance_requests

    def initialize(*pages, balances: NORDEA_CARD_BALANCES)
      @pages = pages
      @balances = balances
      @requests = []
      @balance_requests = []
    end

    def balances(account_uid:)
      @balance_requests << account_uid
      raise EnableBanking::Client::Error, "balances unavailable" if @balances == :error

      @balances
    end

    def transactions(account_uid:, date_from:, continuation_key: nil)
      @requests << { account_uid: account_uid, date_from: date_from, continuation_key: continuation_key }
      index = continuation_key ? continuation_key.delete_prefix("page-").to_i : 0
      next_key = index + 1 < @pages.size ? "page-#{index + 1}" : nil
      { "transactions" => @pages[index], "continuation_key" => next_key }
    end
  end

  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
  end

  def txn(ref, status: "BOOK", indicator: "DBIT", amount: "12.50", date: "2026-10-01", **extra)
    {
      "entry_reference" => ref,
      "status" => status,
      "credit_debit_indicator" => indicator,
      "transaction_amount" => { "amount" => amount, "currency" => "EUR" },
      "booking_date" => (status == "BOOK" ? date : nil),
      "transaction_date" => date,
      "creditor" => { "name" => "K-Market" },
      "debtor" => { "name" => "Employer Oy" },
      "remittance_information" => [ "Card purchase", "" ]
    }.merge(extra)
  end

  test "first sync follows every page and maps amounts, counterparties and dates" do
    client = PagedClient.new([ txn("a"), txn("b", indicator: "CRDT", amount: "2500.00") ], [ txn("c", status: "PDNG") ])

    assert_equal 2, BankTransactions::Sync.new(@account, client: client).call

    assert_equal [ nil, "page-1" ], client.requests.map { |r| r[:continuation_key] }
    assert_equal 1.year.ago.to_date, client.requests.first[:date_from]

    spend = @account.bank_transactions.find_by!(entry_reference: "a")
    assert_equal BigDecimal("-12.50"), spend.amount
    assert_equal "K-Market", spend.counterparty_name
    assert_equal "Card purchase", spend.description
    assert spend.booked?

    salary = @account.bank_transactions.find_by!(entry_reference: "b")
    assert_equal BigDecimal("2500.00"), salary.amount
    assert_equal "Employer Oy", salary.counterparty_name

    hold = @account.bank_transactions.find_by!(entry_reference: "c")
    assert hold.pending?
    assert_nil hold.booking_date
    assert_equal Date.new(2026, 10, 1), hold.occurred_on

    assert_not_nil @account.reload.last_synced_at
  end

  test "re-syncing never duplicates and only counts new booked transactions" do
    BankTransactions::Sync.new(@account, client: PagedClient.new([ txn("a"), txn("b") ])).call
    first_seen = @account.bank_transactions.find_by!(entry_reference: "a").created_at
    travel 1.day

    new_count = BankTransactions::Sync.new(@account, client: PagedClient.new([ txn("a"), txn("b"), txn("c") ])).call

    assert_equal 1, new_count
    assert_equal %w[a b c], @account.bank_transactions.order(:entry_reference).pluck(:entry_reference)
    assert_equal first_seen, @account.bank_transactions.find_by!(entry_reference: "a").created_at
  end

  test "re-syncing keeps a booked transaction's category" do
    BankTransactions::Sync.new(@account, client: PagedClient.new([ txn("a") ])).call
    groceries = TransactionCategory.create!(name: "Groceries", kind: :expense)
    @account.bank_transactions.find_by!(entry_reference: "a").update!(transaction_category: groceries)

    BankTransactions::Sync.new(@account, client: PagedClient.new([ txn("a") ])).call

    assert_equal groceries, @account.bank_transactions.find_by!(entry_reference: "a").transaction_category
  end

  test "pending transactions are replaced: booked versions and cancelled holds leave no duplicates" do
    BankTransactions::Sync.new(@account, client: PagedClient.new([ txn("hold-1", status: "PDNG"), txn("hold-2", status: "PDNG") ])).call

    # hold-1 got booked under a new reference, hold-2 was cancelled
    BankTransactions::Sync.new(@account, client: PagedClient.new([ txn("booked-1") ])).call

    assert_equal [ "booked-1" ], @account.bank_transactions.pluck(:entry_reference)
  end

  test "transactions without an entry_reference get a stable fingerprint" do
    twin = txn(nil, status: "PDNG")
    client = -> { PagedClient.new([ twin, twin.dup, txn("a") ]) }

    BankTransactions::Sync.new(@account, client: client.call).call
    first_refs = @account.bank_transactions.pending.order(:entry_reference).pluck(:entry_reference)
    BankTransactions::Sync.new(@account, client: client.call).call

    assert_equal 2, first_refs.size
    assert first_refs.all? { |ref| ref.start_with?("fp:") }
    assert_equal first_refs, @account.bank_transactions.pending.order(:entry_reference).pluck(:entry_reference)
    assert_equal 3, @account.bank_transactions.count
  end

  test "later syncs start two weeks before the newest booked transaction" do
    BankTransactions::Sync.new(@account, client: PagedClient.new([ txn("a", date: "2026-10-01") ])).call
    client = PagedClient.new([])

    BankTransactions::Sync.new(@account, client: client).call

    assert_equal Date.new(2026, 9, 17), client.requests.first[:date_from]
  end

  test "records the day's balances, replacing an earlier snapshot from the same day" do
    BankTransactions::Sync.new(@account, client: PagedClient.new([ txn("a") ])).call

    snapshot = @account.balances.sole
    assert_equal Time.find_zone("Europe/Helsinki").today, snapshot.on
    assert_equal BigDecimal("-2345.67"), snapshot.booked
    assert_equal BigDecimal("2654.33"), snapshot.available
    assert_equal "ITBD", snapshot.raw.last["balance_type"]

    later = PagedClient.new([ txn("a") ], balances: [ { "balance_type" => "ITBD", "balance_amount" => { "amount" => "-6500.00", "currency" => "EUR" } } ])
    BankTransactions::Sync.new(@account, client: later).call

    assert_equal BigDecimal("-6500.00"), @account.balances.sole.booked
    assert_nil @account.balances.sole.available
    assert_equal [ "acc-1" ], later.balance_requests

    travel 1.day
    BankTransactions::Sync.new(@account, client: later).call

    assert_equal 2, @account.balances.count
  end

  test "a balances response without a usable balance records nothing" do
    client = PagedClient.new([ txn("a") ], balances: [ { "balance_type" => "OTHR", "balance_amount" => { "amount" => "100.00", "currency" => "EUR" } } ])

    BankTransactions::Sync.new(@account, client: client).call

    assert_empty @account.balances
  end

  test "a failed balances request keeps the transactions saved before it" do
    client = PagedClient.new([ txn("a") ], balances: :error)

    error = assert_raises(EnableBanking::Client::Error) { BankTransactions::Sync.new(@account, client: client).call }

    assert_match "balances unavailable", error.message
    assert_equal 1, @account.bank_transactions.count
    assert_empty @account.balances
  end
end
