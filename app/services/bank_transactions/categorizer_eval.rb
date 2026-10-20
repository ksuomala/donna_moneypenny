module BankTransactions
  # Tests the categorizer on transactions that already have a category: a random sample is sent
  # as if it were new, with its own decisions hidden from the context, and the answers are
  # compared with the categories the transactions have. Writes nothing to the transactions; the
  # decisions are kept as an eval run. Precision is reported separately for transactions whose
  # counterparty had the same category on the same account outside the sample (precedent) and
  # for the rest, since precedent makes the first group easier.
  class CategorizerEval
    Row = Data.define(:transaction, :verdict, :precedent) do
      def correct? = verdict.category_id == transaction.transaction_category_id
    end

    # seed: the same seed picks the same sample, so models can be compared on identical transactions.
    def initialize(sample:, since: nil, batch_size: Rails.configuration.x.categorizer.batch_size, model: Rails.configuration.x.categorizer.model, seed: nil)
      @seed = seed
      @sample = sample
      @since = since
      @batch_size = batch_size
      @model = model
    end

    attr_reader :run, :rows

    def call
      scope = BankTransaction.booked.where.not(transaction_category_id: nil)
      scope = scope.where(occurred_on: @since..) if @since
      order = @seed ? Arel.sql("RAND(#{Integer(@seed)})") : Arel.sql("RAND()")
      transactions = scope.order(order).limit(@sample).to_a
      ids = transactions.map(&:id)

      categorizer = Categorizer.new(excluding: ids, model: @model)
      precedents = Categorization.known_decisions(excluding: ids).map { |name, account_id, category_id, _| [ name, account_id, category_id ] }.to_set
      @run = CategorizationRun.create!(mode: :eval, model: @model, prompt_version: Categorizer.prompt_version, rules_digest: Categorizer.rules_digest,
                                       started_at: Time.current, transactions_count: transactions.size)
      @rows = []

      transactions.each_slice(@batch_size) do |batch|
        result = categorizer.call(batch)
        @run.add_usage!(result.usage)
        verdicts = result.verdicts.index_by(&:transaction_id)
        batch.each do |t|
          @rows << Row.new(t, verdicts.fetch(t.id), precedents.include?([ t.counterparty_name, t.bank_account_id, t.transaction_category_id ]))
        end
      end

      store!
      self
    rescue StandardError => e
      @run&.update!(error: "#{e.class}: #{e.message}".first(1000), finished_at: Time.current)
      raise
    end

    def report
      names = TransactionCategory.pluck(:id, :name).to_h
      lines = [ "# eval run #{run.id} with #{run.model}#{" (seed #{@seed})" if @seed}: #{rows.size} categorized transactions sent as new, cost ~#{run.cost&.round(3)} USD" ]
      lines << "# group, transactions, confident, confident correct, confident precision, unsure guesses correct"
      { "all" => rows, "with precedent" => rows.select(&:precedent), "without precedent" => rows.reject(&:precedent) }.each do |label, group|
        confident = group.select { |r| r.verdict.confident? }
        unsure = group - confident
        precision = confident.any? ? "#{(100.0 * confident.count(&:correct?) / confident.size).round(1)}%" : "-"
        lines << [ label, group.size, confident.size, confident.count(&:correct?), precision, "#{unsure.count(&:correct?)}/#{unsure.size}" ].join("\t")
      end

      wrong = rows.select { |r| r.verdict.confident? && !r.correct? }
      lines << "" << "# wrong confident decisions (#{wrong.size}): id, date, amount, counterparty, description, actual, decided, reason"
      wrong.each do |r|
        t = r.transaction
        lines << [ t.id, t.occurred_on, t.amount.to_s("F"), t.counterparty_name, t.description, names[t.transaction_category_id],
                   names[r.verdict.category_id], r.verdict.reason ].map { |v| v.to_s.squish }.join("\t")
      end

      lines << "" << "# confusion: actual, decided, count (wrong ones only, unsure included)"
      rows.reject(&:correct?).group_by { |r| [ names[r.transaction.transaction_category_id], names[r.verdict.category_id] || "(none)" ] }
        .sort_by { |_, group| -group.size }.each { |(actual, decided), group| lines << [ actual, decided, group.size ].join("\t") }
      lines.join("\n")
    end

    private

    def store!
      confident = rows.count { |r| r.verdict.confident? }
      CategorizationDecision.insert_all!(rows.map do |r|
        v = r.verdict
        { categorization_run_id: run.id, bank_transaction_id: v.transaction_id, transaction_category_id: v.category_id, loan_id: v.loan_id,
          confidence: CategorizationDecision.confidences.fetch(v.confidence), reason: v.reason, guard: v.guard, created_at: Time.current }
      end) if rows.any?
      run.update!(confident_count: confident, unsure_count: rows.size - confident, finished_at: Time.current)
    end
  end
end
