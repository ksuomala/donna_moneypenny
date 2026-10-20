require "test_helper"

class BankTransactions::CategorizerTest < ActiveSupport::TestCase
  Message = Struct.new(:stop_reason, :parsed_output, :usage, :model, keyword_init: true)
  Usage = Struct.new(:input_tokens, :output_tokens, :cache_read_input_tokens, :cache_creation_input_tokens, keyword_init: true)

  # Answers every request with the same canned message and records the requests.
  class StubClient
    attr_reader :requests

    def initialize(decisions: [], stop_reason: :end_turn, parsed_output: :from_decisions)
      @message = Message.new(
        stop_reason: stop_reason,
        parsed_output: parsed_output == :from_decisions ? BankTransactions::CategorizerTest.decisions(*decisions) : parsed_output,
        usage: Usage.new(input_tokens: 1200, output_tokens: 300, cache_read_input_tokens: 1000, cache_creation_input_tokens: 0),
        model: "claude-test"
      )
      @requests = []
    end

    def messages = self

    def create(**params)
      @requests << params
      @message
    end
  end

  # Builds the answer the way the SDK parses it from the API's JSON.
  def self.decisions(*rows)
    Anthropic::Internal::Type::Converter.coerce(BankTransactions::Categorizer::Decisions, { decisions: rows })
  end

  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
    @rental = connection.bank_accounts.create!(uid: "acc-2", name: "Vuokratili", currency: "EUR")
    @card = CreditCard.create!(bank_connection: connection, uid: "card", name: "Credit Card", currency: "EUR")
    @groceries = TransactionCategory.create!(name: "Groceries", kind: :expense, description: "Grocery chains")
    @own = TransactionCategory.create!(name: "Own", exclude_from_stats: true)
    @loans = TransactionCategory.create!(name: "Loans", exclude_from_stats: true)
    @investment = TransactionCategory.create!(name: "Investment", kind: :investment)
    @apartment = TransactionCategory.create!(name: "Apartment A", kind: :investment, parent: @investment)
    @mortgage = Loan.create!(name: "Mortgage", creditor: "Nordea")
  end

  def transaction(account, ref, counterparty: "K-Market", amount: -12.5, bank_code: nil, **attributes)
    defaults = { entry_reference: ref, status: "booked", occurred_on: Date.new(2026, 10, 1), amount: amount, currency: "EUR",
                 counterparty_name: counterparty, raw: bank_code && { "bank_transaction_code" => { "description" => bank_code } } }
    account.bank_transactions.create!(defaults.merge(attributes))
  end

  def categorize(transactions, client:, **options)
    BankTransactions::Categorizer.new(client: client, model: "claude-test", **options).call(transactions)
  end

  def decision(transaction, category, confidence: "confident", reason: "matches", loan: nil)
    { transaction_id: transaction.id, category_id: category&.id, loan_id: loan&.id, confidence: confidence, reason: reason }
  end

  test "sends the prompt, the context and the batch with its possible other sides, and returns the verdicts" do
    purchase = transaction(@account, "a", description: "Card purchase")
    payment = transaction(@account, "b", counterparty: "Card issuer", amount: -500, reference_number: "123")
    other_side = transaction(@card, "c", counterparty: nil, amount: 500, status: "pending", bank_code: "Suoritus", occurred_on: Date.new(2026, 10, 3))
    client = StubClient.new(decisions: [ decision(purchase, @groceries, reason: "Grocery chain"), decision(payment, @own, reason: "Card payment") ])

    result = categorize([ purchase, payment ], client: client)

    request = client.requests.sole
    assert_equal "claude-test", request[:model]
    assert_equal 16_000, request[:max_tokens]
    assert_includes request[:system_].first[:text], "# Signals, strongest first"
    assert_equal({ type: "ephemeral" }, request[:system_].first[:cache_control])
    assert_includes request[:system_].second[:text], "# categories: id, name, kind, parent, description"
    assert_equal({ effort: "medium", format: BankTransactions::Categorizer::Decisions }, request[:output_config])
    content = request[:messages].sole[:content]
    assert_includes content, "#{purchase.id}\t#{@account.id}\t2026-10-01\t-12.5\tEUR\tK-Market\tCard purchase\t\t\t"
    assert_includes content, "#{payment.id}\t#{other_side.id}\t#{@card.id}\tpending\t2026-10-03\t500.0\t\tSuoritus\t"

    assert_equal [ [ purchase.id, @groceries.id, nil, "confident", "Grocery chain", nil ], [ payment.id, @own.id, nil, "confident", "Card payment", nil ] ],
                 result.verdicts.map { |v| v.to_h.values }
    assert result.verdicts.first.confident?
    assert_equal [ 1200, 300, 1000, 0 ], result.usage.to_h.values
    assert_equal "claude-test", result.model
  end

  test "guardrails turn risky confident decisions into unsure ones" do
    parent = transaction(@account, "a")
    unknown = transaction(@account, "b")
    nothing = transaction(@account, "c")
    large = transaction(@account, "d", counterparty: "Big Shop", amount: -1500)
    large_known = transaction(@account, "e", amount: -1500)
    transaction(@account, "precedent", amount: -1400, transaction_category: @groceries)
    unpaired = transaction(@account, "f", counterparty: "Me", amount: -200, bank_code: "Tilisiirto")
    internal = transaction(@account, "g", counterparty: "Me", amount: -300, bank_code: "Oma siirto")
    loan = transaction(@account, "h", counterparty: "Bank", amount: -400)
    misloan = transaction(@account, "i", amount: -5)
    ghost_loan = transaction(@account, "j", counterparty: "Bank", amount: -400)
    client = StubClient.new(decisions: [
      decision(parent, @investment), decision(unknown, nil).merge(category_id: 0), decision(nothing, nil), decision(large, @groceries),
      decision(large_known, @groceries), decision(unpaired, @own), decision(internal, @own), decision(loan, @loans, loan: @mortgage),
      decision(misloan, @groceries, loan: @mortgage), decision(ghost_loan, @loans).merge(loan_id: 0)
    ])

    verdicts = categorize([ parent, unknown, nothing, large, large_known, unpaired, internal, loan, misloan, ghost_loan ], client: client).verdicts.index_by(&:transaction_id)

    assert_equal [ nil, "unsure", "invalid category" ], verdicts[parent.id].then { |v| [ v.category_id, v.confidence, v.guard ] }
    assert_equal [ nil, "unsure", "invalid category" ], verdicts[unknown.id].then { |v| [ v.category_id, v.confidence, v.guard ] }
    assert_equal [ nil, "unsure", "confident without category" ], verdicts[nothing.id].then { |v| [ v.category_id, v.confidence, v.guard ] }
    assert_equal [ @groceries.id, "unsure", "large amount without precedent" ], verdicts[large.id].then { |v| [ v.category_id, v.confidence, v.guard ] }
    assert_equal [ @groceries.id, "confident", nil ], verdicts[large_known.id].then { |v| [ v.category_id, v.confidence, v.guard ] }
    assert_equal [ @own.id, "unsure", "own transfer without other side" ], verdicts[unpaired.id].then { |v| [ v.category_id, v.confidence, v.guard ] }
    assert_equal [ @own.id, "confident", nil ], verdicts[internal.id].then { |v| [ v.category_id, v.confidence, v.guard ] }
    assert_equal [ @loans.id, @mortgage.id, "confident" ], verdicts[loan.id].then { |v| [ v.category_id, v.loan_id, v.confidence ] }
    assert_equal [ @groceries.id, nil ], verdicts[misloan.id].then { |v| [ v.category_id, v.loan_id ] }
    assert_equal [ @loans.id, nil, "confident" ], verdicts[ghost_loan.id].then { |v| [ v.category_id, v.loan_id, v.confidence ] }
  end

  test "an unsure decision keeps its guess, decisions outside the batch are dropped, duplicates keep the first, left-out rows become unsure" do
    guessed = transaction(@account, "a")
    repeated = transaction(@account, "b")
    left_out = transaction(@account, "c")
    outsider = transaction(@rental, "d")
    client = StubClient.new(decisions: [
      decision(guessed, @groceries, confidence: "unsure", reason: "Could be a cafe"), decision(repeated, @groceries),
      decision(repeated, @apartment, reason: "second thoughts"), decision(outsider, @groceries)
    ])

    verdicts = categorize([ guessed, repeated, left_out ], client: client).verdicts

    assert_equal [ guessed.id, repeated.id, left_out.id ], verdicts.map(&:transaction_id)
    assert_equal [ @groceries.id, "unsure", "Could be a cafe", nil ], verdicts.first.then { |v| [ v.category_id, v.confidence, v.reason, v.guard ] }
    assert_equal [ @groceries.id, "confident" ], verdicts.second.then { |v| [ v.category_id, v.confidence ] }
    assert_equal [ nil, "unsure", "no decision", "missing" ], verdicts.third.then { |v| [ v.category_id, v.confidence, v.reason, v.guard ] }
  end

  test "a truncated, refused or unparseable answer raises" do
    row = transaction(@account, "a")

    assert_raises(BankTransactions::Categorizer::Truncated) { categorize([ row ], client: StubClient.new(stop_reason: :max_tokens, parsed_output: { error: "cut" })) }
    assert_raises(BankTransactions::Categorizer::Refused) { categorize([ row ], client: StubClient.new(stop_reason: :refusal, parsed_output: nil)) }
    error = assert_raises(BankTransactions::Categorizer::Error) { categorize([ row ], client: StubClient.new(parsed_output: { error: "unexpected token" })) }
    assert_match "unexpected token", error.message
  end

  test "excluding hides the given transactions from the context, the precedents and the other sides" do
    hidden = transaction(@account, "a", amount: -1500, transaction_category: @groceries)
    hidden_pair = transaction(@rental, "b", counterparty: "Me", amount: 1500, transaction_category: @own)
    shown = transaction(@account, "c", amount: -5, transaction_category: @groceries)
    row = transaction(@account, "d", counterparty: "Me", amount: -1500)
    client = StubClient.new(decisions: [ decision(row, @groceries) ])

    categorizer = BankTransactions::Categorizer.new(client: client, model: "claude-test", excluding: [ hidden.id, hidden_pair.id ])
    result = categorizer.call([ row ])

    assert_includes categorizer.context, "K-Market\t#{@account.id}\tGroceries\t1"
    assert_not_includes categorizer.context, "Me\t"
    content = client.requests.sole[:messages].sole[:content]
    assert_includes content, "#{row.id}\t#{hidden_pair.id}\t#{@rental.id}\tbooked\t2026-10-01\t1500.0\tMe\t\t"
    assert_not_includes content, "\tOwn"
    assert_equal "large amount without precedent", result.verdicts.sole.guard
    assert_includes BankTransactions::Categorizer.new(client: client, model: "claude-test").context, "Me\t#{@rental.id}\tOwn\t1"
  end

  test "Haiku 4.5 gets no effort setting, newer models do" do
    row = transaction(@account, "a")
    client = StubClient.new(decisions: [ decision(row, @groceries) ])

    BankTransactions::Categorizer.new(client: client, model: "claude-haiku-4-5").call([ row ])
    BankTransactions::Categorizer.new(client: client, model: "claude-opus-5-5", effort: "low").call([ row ])

    assert_equal [ { format: BankTransactions::Categorizer::Decisions }, { effort: "low", format: BankTransactions::Categorizer::Decisions } ],
                 client.requests.map { |r| r[:output_config] }
  end

  test "costs are estimated per model" do
    run = CategorizationRun.new(model: "claude-haiku-4-5", input_tokens: 1_000_000, output_tokens: 100_000, cache_read_input_tokens: 0, cache_creation_input_tokens: 0)

    assert_in_delta 1.5, run.cost
    assert_nil CategorizationRun.new(model: "other", input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0).cost
  end

  test "prompt and rules versions change with their sources" do
    version = BankTransactions::Categorizer.prompt_version
    digest = BankTransactions::Categorizer.rules_digest

    assert_match(/\A\h{12}\z/, version)
    @groceries.update!(description: "Grocery chains and markets")
    assert_not_equal digest, BankTransactions::Categorizer.rules_digest
    assert_equal version, BankTransactions::Categorizer.prompt_version
  end
end
