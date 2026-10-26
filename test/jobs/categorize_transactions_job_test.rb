require "test_helper"

class CategorizeTransactionsJobTest < ActiveJob::TestCase
  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
    @groceries = TransactionCategory.create!(name: "Groceries", kind: :expense, description: "Grocery chains")
    @loans = TransactionCategory.create!(name: "Loans", exclude_from_stats: true)
    @mortgage = Loan.create!(name: "Mortgage", creditor: "Nordea")
    @config = Rails.configuration.x.categorizer
    @saved = @config.to_h.dup
    @config.batch_size = 2
    @config.max_per_run = 500
    @config.cooldown_days = 7
    @config.apply = false
    @config.model = "claude-test"
  end

  teardown { @saved.each { |key, value| @config.public_send(:"#{key}=", value) } }

  def transaction(ref, counterparty: "K-Market", amount: -12.5, **attributes)
    @account.bank_transactions.create!(entry_reference: ref, status: "booked", occurred_on: Date.new(2026, 10, 1),
                                       amount: amount, currency: "EUR", counterparty_name: counterparty, **attributes)
  end

  # K-Market rows are confident Groceries, Bank rows confident Loans on the mortgage, the rest unsure.
  def stub
    CategorizerStub.new do |ids|
      BankTransaction.find(ids).map do |t|
        case t.counterparty_name
        when "K-Market" then { transaction_id: t.id, category_id: @groceries.id, loan_id: nil, confidence: "confident", reason: "chain" }
        when "Bank" then { transaction_id: t.id, category_id: @loans.id, loan_id: @mortgage.id, confidence: "confident", reason: "loan" }
        else { transaction_id: t.id, category_id: @groceries.id, loan_id: nil, confidence: "unsure", reason: "no idea" }
        end
      end
    end
  end

  def run_all(client)
    CategorizerStub.with(client) { perform_enqueued_jobs { CategorizeTransactionsJob.perform_later } }
  end

  test "shadow mode decides every uncategorized booked row in batches and writes nothing" do
    rows = [ transaction("a"), transaction("b", counterparty: "Cafe"), transaction("c") ]
    transaction("done", transaction_category: @groceries)
    transaction("p", status: "pending")
    client = stub

    run_all(client)

    run = CategorizationRun.sole
    assert run.shadow?
    assert run.finished?
    assert_nil run.error
    assert_equal [ 3, 2, 1, 0 ], [ run.transactions_count, run.confident_count, run.unsure_count, run.applied_count ]
    assert_equal [ 2000, 200, 1600 ], [ run.input_tokens, run.output_tokens, run.cache_read_input_tokens ]
    assert_equal 2, client.requests.size
    assert_equal rows.map(&:id).sort, run.decisions.pluck(:bank_transaction_id).sort
    assert rows.all? { |t| t.reload.transaction_category.nil? }
    assert_includes run.unsure_lines, "\tCafe\t\tGroceries\t\tno idea\t"
  end

  test "apply mode writes the confident decisions and their loans, and nothing else" do
    @config.apply = true
    shop = transaction("a")
    loan = transaction("b", counterparty: "Bank", amount: -400)
    unsure = transaction("c", counterparty: "Cafe")

    run_all(stub)

    run = CategorizationRun.sole
    assert run.apply?
    assert_equal 2, run.applied_count
    assert_equal @groceries, shop.reload.transaction_category
    assert_equal [ @loans, @mortgage ], [ loan.reload.transaction_category, loan.loan ]
    assert_nil unsure.reload.transaction_category
    assert_equal [ shop.id, loan.id ].sort, run.decisions.where(applied: true).pluck(:bank_transaction_id).sort
  end

  test "rows decided recently are skipped until the cooldown passes or a description changes" do
    row = transaction("a", counterparty: "Cafe")
    run_all(stub)
    run_all(stub)
    assert_equal [ 1, 0 ], CategorizationRun.order(:id).pluck(:transactions_count)

    @groceries.update!(description: "Grocery chains and markets")
    run_all(stub)
    assert_equal 1, CategorizationRun.order(:id).last.transactions_count

    travel 8.days do
      run_all(stub)
      assert_equal 1, CategorizationRun.order(:id).last.transactions_count
    end

    @config.model = "claude-other"
    run_all(stub)
    assert_equal 1, CategorizationRun.order(:id).last.transactions_count
    assert_equal 4, row.categorization_decisions.count
  end

  test "the cap limits a run" do
    3.times { |i| transaction("r#{i}") }

    CategorizerStub.with(stub) { perform_enqueued_jobs { CategorizeTransactionsJob.perform_later(limit: 2) } }

    assert_equal 2, CategorizationRun.sole.transactions_count
  end

  test "a truncated answer splits the batch, an API error ends the run with the error" do
    2.times { |i| transaction("r#{i}") }
    truncating = Class.new(CategorizerStub) do
      def create(**params)
        rows = params[:messages].sole[:content].lines.count { |l| l =~ /\A\d/ && l.split("\t").size == 10 }
        return CategorizerStub::Message.new(stop_reason: :max_tokens, parsed_output: { error: "cut" }, usage: nil, model: "x") if rows > 1

        super
      end
    end.new { |ids| ids.map { |id| { transaction_id: id, category_id: @groceries.id, loan_id: nil, confidence: "confident", reason: "chain" } } }

    run_all(truncating)
    assert_equal [ 2, nil ], CategorizationRun.sole.then { |run| [ run.decisions.count, run.error ] }

    transaction("x")
    failing = CategorizerStub.new(raises: Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com"), message: "down"))
    error = CategorizerStub.with(failing) do
      CategorizeTransactionsJob.perform_now(user_id: User.owner.id)
    rescue Anthropic::Errors::APIConnectionError => e
      e
    end
    assert_kind_of Anthropic::Errors::APIConnectionError, error
    run = CategorizationRun.order(:id).last
    assert run.finished?
    assert_match "down", run.error
  end

  test "does nothing without an API key" do
    transaction("a")
    backend = BankTransactions::Categorizer::AnthropicBackend
    stubbed_factory, api_key = backend.client_factory, backend.method(:api_key)
    backend.client_factory = backend::DEFAULT_CLIENT_FACTORY
    backend.define_singleton_method(:api_key) { nil }

    perform_enqueued_jobs { CategorizeTransactionsJob.perform_later }

    assert_empty CategorizationRun.all
  ensure
    backend.client_factory = stubbed_factory if stubbed_factory
    backend.define_singleton_method(:api_key, api_key) if api_key
  end

  test "every user with categories gets a run of their own, built from their own data, and only their categories are accepted" do
    @config.apply = true
    other_user = User.where.not(id: User.owner.id).first
    theirs = BankConnection.create!(user: other_user, session_id: "s2", aspsp_name: "Danske Bank", aspsp_country: "DK", valid_until: 1.month.from_now)
    other = theirs.bank_accounts.create!(uid: "acc-2", name: "Lønkonto", currency: "DKK")
    their_groceries = TransactionCategory.create!(user: other_user, name: "Dagligvarer", kind: :expense)
    their_row = other.bank_transactions.create!(entry_reference: "x", status: "booked", occurred_on: Date.new(2026, 10, 1), amount: -5, currency: "EUR", counterparty_name: "Netto")
    their_cafe = other.bank_transactions.create!(entry_reference: "y", status: "booked", occurred_on: Date.new(2026, 10, 2), amount: -3, currency: "EUR", counterparty_name: "Cafe")
    mine = transaction("a")
    contexts = []
    # The right category for each user's groceries; for the cafe the owner's category, which is not theirs.
    client = CategorizerStub.new do |ids|
      BankTransaction.find(ids).map do |t|
        category = { "K-Market" => @groceries, "Netto" => their_groceries, "Cafe" => @groceries }.fetch(t.counterparty_name)
        { transaction_id: t.id, category_id: category.id, loan_id: nil, confidence: "confident", reason: "chain" }
      end
    end
    client.define_singleton_method(:create) { |**params| contexts << params[:system_].second[:text]; super(**params) }

    run_all(client)

    runs = CategorizationRun.order(:id).to_a
    assert_equal [ User.owner, other_user ], runs.map(&:user)
    assert_equal [ [ 1, 1, 0, 1 ], [ 2, 1, 1, 1 ] ], runs.map { |r| [ r.transactions_count, r.confident_count, r.unsure_count, r.applied_count ] }
    assert_equal @groceries, mine.reload.transaction_category
    assert_equal their_groceries, their_row.reload.transaction_category
    assert_nil their_cafe.reload.transaction_category
    assert_equal "invalid category", runs.last.decisions.find_by(bank_transaction: their_cafe).guard
    assert_equal [ mine.id ], runs.first.decisions.pluck(:bank_transaction_id)

    mine_context, theirs_context = contexts
    assert_includes mine_context, "Groceries"
    assert_includes mine_context, @account.name
    assert_not_includes mine_context, "Dagligvarer"
    assert_not_includes mine_context, other.name
    assert_includes theirs_context, "Dagligvarer"
    assert_includes theirs_context, other.name
    assert_not_includes theirs_context, "Groceries"
    assert_not_includes theirs_context, @account.name
  end

  test "a user without categories gets no run" do
    transaction("a")
    other_user = User.where.not(id: User.owner.id).first
    BankConnection.create!(user: other_user, session_id: "s2", aspsp_name: "Revolut", aspsp_country: "LT", valid_until: 1.month.from_now)
      .bank_accounts.create!(uid: "acc-2", currency: "EUR")
      .bank_transactions.create!(entry_reference: "x", status: "booked", occurred_on: Date.new(2026, 10, 1), amount: -5, currency: "EUR", counterparty_name: "K-Market")

    run_all(stub)

    assert_equal [ User.owner ], CategorizationRun.all.map(&:user)
  end
end
