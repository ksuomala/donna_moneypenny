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

  test "a large Own transfer is backed by its other side: booked, unambiguous, and Own already or confidently Own in the batch" do
    paid = transaction(@account, "p1", counterparty: "Card Issuer", amount: -3000, transaction_category: @own)
    payment = transaction(@card, "c1", counterparty: nil, amount: 3000, bank_code: "Suoritus")
    out = transaction(@card, "c2", counterparty: nil, amount: -6500, bank_code: "Tilisiirto", occurred_on: Date.new(2026, 10, 2))
    into = transaction(@account, "p2", counterparty: "Me", amount: 6500, bank_code: "Oma siirto", occurred_on: Date.new(2026, 10, 2))
    waiting = transaction(@card, "c3", counterparty: nil, amount: 2000, bank_code: "Suoritus", occurred_on: Date.new(2026, 10, 3))
    transaction(@account, "p3", counterparty: "Card Issuer", amount: -2000, status: "pending", occurred_on: Date.new(2026, 10, 3))
    twice = transaction(@card, "c4", counterparty: nil, amount: 1500, bank_code: "Suoritus", occurred_on: Date.new(2026, 10, 4))
    transaction(@account, "p4", counterparty: "Card Issuer", amount: -1500, transaction_category: @own, occurred_on: Date.new(2026, 10, 4))
    transaction(@rental, "p5", counterparty: "Card Issuer", amount: -1500, transaction_category: @groceries, occurred_on: Date.new(2026, 10, 4))
    big_shop = transaction(@account, "s1", counterparty: "Big Shop", amount: -2500)
    client = StubClient.new(decisions: [ payment, out, into, waiting, twice ].map { |t| decision(t, @own) } + [ decision(big_shop, @groceries) ])

    verdicts = categorize([ payment, out, into, waiting, twice, big_shop ], client: client).verdicts.index_by(&:transaction_id)

    assert_equal [ "confident", nil ], verdicts[payment.id].to_h.values_at(:confidence, :guard), "other side already Own"
    assert_equal [ "confident", nil ], verdicts[out.id].to_h.values_at(:confidence, :guard), "both halves in the batch, both Own"
    assert_equal [ "confident", nil ], verdicts[into.id].to_h.values_at(:confidence, :guard)
    assert_equal [ "unsure", "large amount without precedent" ], verdicts[waiting.id].to_h.values_at(:confidence, :guard), "other side pending"
    assert_equal [ "unsure", "large amount without precedent" ], verdicts[twice.id].to_h.values_at(:confidence, :guard), "two candidates, one not Own"
    assert_equal [ "unsure", "large amount without precedent" ], verdicts[big_shop.id].to_h.values_at(:confidence, :guard), "not Own: name precedent still required"
    assert_equal @own, paid.reload.transaction_category
  end

  test "a large Own transfer loses its backing when its partner in the batch is downgraded" do
    out = transaction(@card, "c1", counterparty: nil, amount: -6500, bank_code: "Tilisiirto")
    into = transaction(@account, "p1", counterparty: "Me", amount: 6500, bank_code: "Oma siirto")
    transaction(@rental, "p2", counterparty: "Me", amount: 6500, status: "pending")
    client = StubClient.new(decisions: [ decision(out, @own), decision(into, @own) ])

    verdicts = categorize([ out, into ], client: client).verdicts.index_by(&:transaction_id)

    assert_equal "unsure", verdicts[out.id].confidence, "its candidates include a pending row"
    assert_equal "unsure", verdicts[into.id].confidence, "its only other side was downgraded"
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

  # Answers OpenAI and TypeSafe requests with a canned JSON body and records the bodies.
  class JsonStub
    attr_reader :bodies

    def initialize(&answer)
      @answer = answer
      @bodies = []
    end

    def post(body)
      @bodies << body
      JSON.parse(@answer.call(body).to_json)
    end
  end

  test "the model ID picks the provider" do
    assert_equal BankTransactions::Categorizer::AnthropicBackend, BankTransactions::Categorizer.backend_for("claude-haiku-4-5")
    assert_equal BankTransactions::Categorizer::OpenaiBackend, BankTransactions::Categorizer.backend_for("gpt-6-luna")
    assert_equal BankTransactions::Categorizer::JevBackend, BankTransactions::Categorizer.backend_for("jev-latest")
  end

  test "OpenAI gets the prompt, context and batch with a strict schema, and its answer goes through the guardrails" do
    shop = transaction(@account, "a")
    big = transaction(@account, "b", counterparty: "Big Shop", amount: -1500)
    client = JsonStub.new do |_|
      { status: "completed", model: "gpt-6-luna",
        output: [ { type: "reasoning" }, { type: "message", content: [ { type: "output_text", text: {
          decisions: [ decision(shop, @groceries), decision(big, @groceries) ] }.to_json } ] } ],
        usage: { input_tokens: 5000, input_tokens_details: { cached_tokens: 4000 }, output_tokens: 300 } }
    end

    result = categorize([ shop, big ], client: client, model: "gpt-6-luna", effort: "low")

    body = client.bodies.sole
    assert_equal "gpt-6-luna", body[:model]
    assert_includes body[:instructions], "# Signals, strongest first"
    assert_includes body[:instructions], "# categories: id, name, kind, parent, description"
    assert_includes body[:input].sole[:content], "#{shop.id}\t#{@account.id}\t2026-10-01"
    assert_equal({ effort: "low" }, body[:reasoning])
    format = body[:text][:format]
    assert_equal [ "json_schema", true ], [ format[:type], format[:strict] ]
    assert_equal %w[integer null], format[:schema].dig(:properties, :decisions, :items, :properties, :category_id, :type)
    assert_equal [ "confident", "unsure" ], result.verdicts.map(&:confidence)
    assert_equal "large amount without precedent", result.verdicts.second.guard
    assert_equal [ 1000, 300, 4000, 0 ], result.usage.to_h.values
    assert_equal "gpt-6-luna", result.model
  end

  test "OpenAI's incomplete or refused answers raise" do
    row = transaction(@account, "a")
    cut = JsonStub.new { |_| { status: "incomplete", incomplete_details: { reason: "max_output_tokens" } } }
    refused = JsonStub.new { |_| { status: "completed", output: [ { type: "message", content: [ { type: "refusal", refusal: "no" } ] } ] } }

    assert_raises(BankTransactions::Categorizer::Truncated) { categorize([ row ], client: cut, model: "gpt-6-luna") }
    assert_raises(BankTransactions::Categorizer::Refused) { categorize([ row ], client: refused, model: "gpt-6-luna") }
  end

  test "Jev gets one category and one loan question per transaction; confidence above the threshold is confident" do
    shop = transaction(@account, "a")
    loan = transaction(@account, "b", counterparty: "Bank", amount: -400)
    client = JsonStub.new do |body|
      { model: "jev-1.14.0", usage: { input_tokens: 9000, output_tokens: 40 },
        answers: {
          "t#{shop.id}" => { type: "choice", choice: "c#{@groceries.id}", confidence: 0.95, probabilities: { "c#{@groceries.id}" => 0.97, "c#{@own.id}" => 0.02 } },
          "l#{shop.id}" => { type: "choice", choice: "none", confidence: 0.99, probabilities: {} },
          "t#{loan.id}" => { type: "choice", choice: "c#{@loans.id}", confidence: 0.6, probabilities: { "c#{@loans.id}" => 0.7 } },
          "l#{loan.id}" => { type: "choice", choice: "l#{@mortgage.id}", confidence: 0.8, probabilities: {} }
        } }
    end

    result = BankTransactions::Categorizer.new(client: client, model: "jev-latest").call([ shop, loan ])

    body = client.bodies.sole
    assert_equal "jev-latest", body[:model]
    assert_includes body[:state], "# categories: id, name, kind, parent, description"
    assert_includes body[:state], "#{shop.id}\t#{@account.id}\t2026-10-01"
    assert_equal %W[t#{shop.id} l#{shop.id} t#{loan.id} l#{loan.id}], body[:questions].keys
    criteria = body[:questions]["t#{shop.id}"][:criteria]
    assert_equal "Groceries", criteria["c#{@groceries.id}"]
    assert_equal "Investment / Apartment A", criteria["c#{@apartment.id}"]
    assert_not criteria.key?("c#{@investment.id}")
    assert_equal [ "Mortgage", "none" ], body[:questions]["l#{shop.id}"][:criteria].then { |c| [ c["l#{@mortgage.id}"], c.keys.last ] }

    shop_verdict, loan_verdict = result.verdicts
    assert_equal [ @groceries.id, nil, "confident", "confidence 0.95; Groceries 0.97, Own 0.02" ], shop_verdict.to_h.values_at(:category_id, :loan_id, :confidence, :reason)
    assert_equal [ @loans.id, @mortgage.id, "unsure" ], loan_verdict.to_h.values_at(:category_id, :loan_id, :confidence)
    assert_equal [ 9000, 40, 0, 0 ], result.usage.to_h.values
  end
end
