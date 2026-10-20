module BankTransactions
  # Decides the categories of a batch of uncategorized transactions with Claude, in one Messages
  # API request with a structured (JSON schema) answer. The model gets the same context the
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

    PROMPT_PATH = Rails.root.join("app/services/bank_transactions/categorizer/prompt.md")
    MAX_TOKENS = 16_000
    LARGE_AMOUNT = 1000
    REQUEST_OPTIONS = { timeout: 600, max_retries: 3 }.freeze

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

    # Tests swap the factory for one returning a stub; the real client needs an API key when
    # it's built, so it's only built when a categorizer is.
    DEFAULT_CLIENT_FACTORY = -> { Anthropic::Client.new(api_key: BankTransactions::Categorizer.api_key) }
    class_attribute :client_factory, default: DEFAULT_CLIENT_FACTORY

    def self.api_key = Rails.application.credentials.dig(:anthropic, :api_key).presence || ENV["ANTHROPIC_API_KEY"].presence

    # Whether a client can be built: false until an API key is in the credentials or the env.
    # Tests that stub the client set the factory, which counts as configured.
    def self.configured? = client_factory != DEFAULT_CLIENT_FACTORY || api_key.present?

    def self.prompt = File.read(PROMPT_PATH)

    # Identifies the prompt text a run was made with.
    def self.prompt_version = Digest::SHA256.hexdigest(prompt).first(12)

    # Identifies the rules a run was made with: the categories and their descriptions.
    def self.rules_digest
      Digest::SHA256.hexdigest(TransactionCategory.order(:id).pluck(:id, :name, :parent_id, :description).to_json).first(12)
    end

    # excluding: transaction ids to hide from the context (the evaluation sends categorized
    # transactions as if they were new, and their own decisions must not be visible).
    def initialize(excluding: [], model: Rails.configuration.x.categorizer.model, effort: Rails.configuration.x.categorizer.effort,
                   client: self.class.client_factory.call)
      @excluding = excluding
      @model = model
      @effort = effort
      @client = client
      @context = Categorization.context(excluding: excluding)
      @precedents = Categorization.known_decisions(excluding: excluding).map { |name, account_id, category_id, _| [ name, account_id, category_id ] }.to_set
    end

    attr_reader :context

    # Decides one batch. Raises Truncated or Refused when there is no usable answer.
    def call(transactions)
      transactions = transactions.to_a
      hints = Categorization.pairing_hints(transactions, hide: @excluding)

      message = @client.messages.create(
        model: @model,
        max_tokens: MAX_TOKENS,
        system_: [
          { type: "text", text: self.class.prompt, cache_control: { type: "ephemeral" } },
          { type: "text", text: @context, cache_control: { type: "ephemeral" } }
        ],
        messages: [ { role: "user", content: user_message(transactions, hints) } ],
        output_config: output_config,
        request_options: REQUEST_OPTIONS
      )

      raise Truncated, "Answer for #{transactions.size} transactions hit #{MAX_TOKENS} tokens" if message.stop_reason == :max_tokens
      raise Refused, "Model refused the batch" if message.stop_reason == :refusal
      parsed = message.parsed_output
      raise Error, "Unusable answer: #{parsed.inspect.first(200)}" unless parsed.is_a?(Decisions)

      Result.new(verdicts: verdicts(parsed.decisions, transactions, hints), usage: usage(message.usage), model: message.model.to_s)
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
                                      other.counterparty_name, other.raw&.dig("bank_transaction_code", "description"), category)
        end
      end
      lines.join("\n")
    end

    # Haiku 4.5 has no effort setting (the API rejects it), the newer models take one.
    def output_config
      @effort.present? && !@model.to_s.start_with?("claude-haiku-4") ? { effort: @effort, format: Decisions } : { format: Decisions }
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

      transactions.map { |t| verdicts[t.id] || Verdict.new(t.id, nil, nil, "unsure", "no decision", "missing") }
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
          confidence, guard = "unsure", "large amount without precedent"
        elsif category.name == "Own" && others.empty? && transaction.raw&.dig("bank_transaction_code", "description") != "Oma siirto"
          confidence, guard = "unsure", "own transfer without other side"
        end
      end
      loan_id = decision.loan_id if category&.name == "Loans" && loan_ids.include?(decision.loan_id)

      Verdict.new(transaction.id, category&.id, loan_id, confidence, reason, guard)
    end

    def usage(usage)
      Usage.new(input_tokens: usage.input_tokens.to_i, output_tokens: usage.output_tokens.to_i,
                cache_read_input_tokens: usage.cache_read_input_tokens.to_i, cache_creation_input_tokens: usage.cache_creation_input_tokens.to_i)
    end
  end
end
