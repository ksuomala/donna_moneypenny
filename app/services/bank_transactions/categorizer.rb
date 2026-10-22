module BankTransactions
  # Decides the categories of a batch of uncategorized transactions with a model (Claude by
  # default; OpenAI and TypeSafe's Jev through the backends in categorizer/), in one request
  # with a structured answer. The model gets the same context the
  # categorize-transactions skill reads (categories with their descriptions, loans, accounts,
  # earlier decisions per counterparty), the batch with every field, and for each transaction
  # the rows that could be the other side of a transfer.
  #
  # Every answer passes through guardrails here before anyone trusts it: unknown or parent
  # categories, large amounts without precedent, own transfers without an other side and loans
  # outside Loans are turned into unsure verdicts. Writing to the database is not this class's
  # job (CategorizeTransactionsJob does it through Categorization.apply, only for confident
  # verdicts, only when the categorizer is switched to apply mode).
  class Categorizer
    Error = Class.new(StandardError)
    # The answer hit max_tokens: the batch is too big, try a smaller one.
    Truncated = Class.new(Error)
    # The model declined the batch.
    Refused = Class.new(Error)

    # Rate limited by a provider without an SDK error of its own (OpenAI, TypeSafe).
    RateLimited = Class.new(Error)

    PROMPT_PATH = Rails.root.join("app/services/bank_transactions/categorizer/prompt.md")
    LARGE_AMOUNT = 1000

    # The JSON schema the model's answer is constrained to.
    class Decision < Anthropic::BaseModel
      required :transaction_id, Integer
      required :category_id, Integer, nil?: true, doc: "A category id from the list, or null when there is no reasonable guess"
      required :loan_id, Integer, nil?: true, doc: "For Loans only: the loan's id when a loan description identifies it, else null"
      required :confidence, Anthropic::EnumOf[:confident, :unsure]
      required :reason, String, doc: "At most 20 words: the signal that decided it, or what is missing"
    end

    class Decisions < Anthropic::BaseModel
      required :decisions, Anthropic::ArrayOf[Decision]
    end

    # One transaction's decision after the guardrails. guard names the guardrail that turned a
    # confident decision into an unsure one, or nil.
    Verdict = Data.define(:transaction_id, :category_id, :loan_id, :confidence, :reason, :guard) do
      def confident? = confidence == "confident"
    end
    Usage = Data.define(:input_tokens, :output_tokens, :cache_read_input_tokens, :cache_creation_input_tokens)
    Result = Data.define(:verdicts, :usage, :model)
    # What a backend returns: decisions shaped like Decision, usage, and the model that answered.
    Response = Data.define(:decisions, :usage, :model)

    # The provider is picked by the model ID: gpt-* and o* go to OpenAI, jev* to TypeSafe, the
    # rest to Anthropic.
    def self.backend_for(model)
      case model.to_s
      when /\A(gpt-|o\d)/ then OpenaiBackend
      when /\Ajev/ then JevBackend
      else AnthropicBackend
      end
    end

    # Whether the model's provider has an API key.
    def self.configured?(model = Rails.configuration.x.categorizer.model) = backend_for(model).configured?

    def self.prompt = File.read(PROMPT_PATH)

    # Identifies the prompt text a run was made with.
    def self.prompt_version = Digest::SHA256.hexdigest(prompt).first(12)

    # Identifies the rules a run was made with: the categories and their descriptions.
    def self.rules_digest
      Digest::SHA256.hexdigest(TransactionCategory.order(:id).pluck(:id, :name, :parent_id, :description).to_json).first(12)
    end

    # excluding: transaction ids to hide from the context (the evaluation sends categorized
    # transactions as if they were new, and their own decisions must not be visible).
    # client: a stand-in for the provider's client, in tests.
    def initialize(excluding: [], model: Rails.configuration.x.categorizer.model, effort: Rails.configuration.x.categorizer.effort, client: nil)
      @excluding = excluding
      @model = model
      @backend = self.class.backend_for(model).new(model: model, effort: effort, client: client)
      @context = Categorization.context(excluding: excluding)
      @precedents = Categorization.known_decisions(excluding: excluding).map { |name, account_id, category_id, _| [ name, account_id, category_id ] }.to_set
    end

    attr_reader :context

    # Decides one batch. Raises Truncated or Refused when there is no usable answer.
    def call(transactions)
      transactions = transactions.to_a
      hints = Categorization.pairing_hints(transactions, hide: @excluding)
      categories = TransactionCategory.includes(:children, :parent).reject { |c| c.children.any? }

      response = @backend.decide(prompt: self.class.prompt, context: @context, user_message: user_message(transactions, hints),
                                 transactions: transactions, categories: categories, loans: Loan.order(:id).to_a)

      Result.new(verdicts: verdicts(response.decisions, transactions, hints), usage: response.usage, model: response.model.presence || @model.to_s)
    end

    # The batch and, for each transaction, the candidate other sides of a transfer.
    def user_message(transactions, hints)
      lines = [ "# transactions to categorize: id, account id, date, amount, currency, counterparty, description, reference, mcc, bank code" ]
      transactions.each { |t| lines << Categorization.transaction_row(t) }

      lines << "" << "# possible other sides (same amount the other way round on another account within 5 days): " \
                     "transaction id, other id, other account id, status, date, amount, counterparty, bank code, category"
      names = TransactionCategory.pluck(:id, :name).to_h
      transactions.each do |t|
        hints.fetch(t.id, []).each do |other|
          category = @excluding.include?(other.id) ? nil : names[other.transaction_category_id]
          lines << Categorization.row(t.id, other.id, other.bank_account_id, other.status, other.occurred_on, other.amount.to_s("F"),
                                      other.counterparty_name, other.bank_code, category)
        end
      end
      lines.join("\n")
    end

    private

    # Applies the guardrails. Decisions for ids outside the batch are dropped, the first decision
    # per id wins, and a transaction the model left out becomes unsure.
    def verdicts(decisions, transactions, hints)
      categories = TransactionCategory.includes(:children).index_by(&:id)
      loan_ids = Loan.pluck(:id).to_set
      by_id = transactions.index_by(&:id)
      verdicts = {}

      decisions.each do |decision|
        transaction = by_id[decision.transaction_id]
        next if transaction.nil? || verdicts.key?(transaction.id)

        verdicts[transaction.id] = verdict(decision, transaction, categories, loan_ids, hints.fetch(transaction.id, []))
      end
      confirm_large_own_transfers(verdicts, by_id, hints, categories)

      transactions.map { |t| verdicts[t.id] || Verdict.new(t.id, nil, nil, "unsure", "no decision", "missing") }
    end

    PAIR_PENDING = "large own transfer, other side unconfirmed"

    # A large Own transfer has no name precedent when it comes without a counterparty (rows on a
    # credit card account never have one). Its other side is the evidence instead. It stays
    # confident when every candidate other side is booked and either already Own or, in this
    # batch, a confident Own decision itself. Repeats until nothing changes, because a
    # downgraded other side takes its partner's backing with it.
    def confirm_large_own_transfers(verdicts, by_id, hints, categories)
      own_id = categories.values.find { |c| c.name == "Own" }&.id
      waiting = verdicts.values.select { |v| v.guard == PAIR_PENDING }
      waiting.each { |v| verdicts[v.transaction_id] = v.with(confidence: "confident", guard: nil) }

      loop do
        changed = false
        waiting.each do |v|
          next unless verdicts[v.transaction_id].confident?

          others = hints.fetch(v.transaction_id, [])
          backed = others.any? && others.all? do |other|
            next false unless other.booked?

            decided = verdicts[other.id] if by_id.key?(other.id)
            decided ? decided.confident? && decided.category_id == own_id : !@excluding.include?(other.id) && other.transaction_category_id == own_id
          end
          next if backed

          verdicts[v.transaction_id] = verdicts[v.transaction_id].with(confidence: "unsure", guard: "large amount without precedent")
          changed = true
        end
        break unless changed
      end
    end

    def verdict(decision, transaction, categories, loan_ids, others)
      category = categories[decision.category_id] if decision.category_id
      confidence = decision.confidence.to_s
      reason = decision.reason.to_s.squish.first(200)
      guard = nil

      if decision.category_id && (category.nil? || category.children.any?)
        category = nil
        confidence, guard = "unsure", "invalid category"
      end
      if confidence == "confident"
        if category.nil?
          confidence, guard = "unsure", "confident without category"
        elsif transaction.amount.abs > LARGE_AMOUNT && !@precedents.include?([ transaction.counterparty_name, transaction.bank_account_id, category.id ])
          # An Own transfer can be backed by its other side instead (confirm_large_own_transfers).
          confidence, guard = "unsure", category.name == "Own" && others.any? ? PAIR_PENDING : "large amount without precedent"
        elsif category.name == "Own" && others.empty? && transaction.bank_code != "Oma siirto"
          confidence, guard = "unsure", "own transfer without other side"
        end
      end
      loan_id = decision.loan_id if category&.name == "Loans" && loan_ids.include?(decision.loan_id)

      Verdict.new(transaction.id, category&.id, loan_id, confidence, reason, guard)
    end
  end
end
