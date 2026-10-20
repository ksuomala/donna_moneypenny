# Decides categories for the uncategorized booked transactions with Claude
# (BankTransactions::Categorizer), one batch per job: Solid Queue runs inside Puma and gets
# seconds on a restart, so no job may run for minutes. The first job of a run picks the
# transactions and creates the CategorizationRun; every job decides one batch, stores the
# decisions, applies the confident ones when the categorizer is in apply mode, and enqueues the
# next batch. Settings come from config/initializers/categorizer.rb. Enqueued after every sync.
class CategorizeTransactionsJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "categorizer"

  RATE_LIMIT_WAIT = 5.minutes

  # run_id and ids continue a run with what's left of it; without them a new run starts.
  # limit caps a new run (default max_per_run); batch_size shrinks after a truncated answer.
  def perform(run_id: nil, ids: nil, limit: nil, batch_size: nil)
    unless BankTransactions::Categorizer.configured?
      Rails.logger.info("[categorizer] no Anthropic API key configured (credentials anthropic.api_key or ANTHROPIC_API_KEY), skipping")
      return
    end

    run, ids = run_id ? [ CategorizationRun.find(run_id), ids ] : start(limit: limit)
    return if run.finished?

    batch_size ||= config.batch_size
    batch, rest = ids.first(batch_size), ids.drop(batch_size)
    decide(run, batch)
    rest.any? ? self.class.perform_later(run_id: run.id, ids: rest, batch_size: batch_size) : run.update!(finished_at: Time.current)
  rescue BankTransactions::Categorizer::Truncated => e
    raise if batch_size == 1

    self.class.perform_later(run_id: run.id, ids: batch + rest, batch_size: [ batch_size / 2, 1 ].max)
    Rails.logger.warn("[categorizer] run #{run.id}: #{e.message}, retrying with batches of #{[ batch_size / 2, 1 ].max}")
  rescue Anthropic::Errors::RateLimitError, BankTransactions::Categorizer::RateLimited => e
    self.class.set(wait: RATE_LIMIT_WAIT).perform_later(run_id: run.id, ids: batch + rest, batch_size: batch_size)
    Rails.logger.warn("[categorizer] run #{run.id}: rate limited (#{e.message}), continuing in #{RATE_LIMIT_WAIT.inspect}")
  rescue StandardError => e
    run&.update!(error: "#{e.class}: #{e.message}".first(1000), finished_at: Time.current)
    raise
  end

  private

  def config = Rails.configuration.x.categorizer

  # A new run over the oldest uncategorized booked transactions, leaving out the ones the same
  # model decided recently under the same rules (a changed category description or another
  # model lifts the cooldown).
  def start(limit:)
    cooled = CategorizationDecision.joins(:run).where(created_at: config.cooldown_days.days.ago..)
      .merge(CategorizationRun.where(rules_digest: BankTransactions::Categorizer.rules_digest, model: config.model, mode: [ :shadow, :apply ]))
      .select(:bank_transaction_id)
    ids = BankTransaction.booked.where(transaction_category_id: nil).where.not(id: cooled).order(:occurred_on, :id).limit(limit || config.max_per_run).pluck(:id)
    run = CategorizationRun.create!(mode: config.apply ? :apply : :shadow, model: config.model, prompt_version: BankTransactions::Categorizer.prompt_version,
                                    rules_digest: BankTransactions::Categorizer.rules_digest, started_at: Time.current,
                                    transactions_count: ids.size, finished_at: (Time.current if ids.empty?))
    [ run, ids ]
  end

  def decide(run, ids)
    transactions = BankTransaction.booked.where(id: ids, transaction_category_id: nil).order(:occurred_on, :id).to_a
    return if transactions.empty?

    result = BankTransactions::Categorizer.new(model: run.model).call(transactions)
    confident = result.verdicts.select(&:confident?)

    CategorizationRun.transaction do
      now = Time.current
      CategorizationDecision.insert_all!(result.verdicts.map do |v|
        { categorization_run_id: run.id, bank_transaction_id: v.transaction_id, transaction_category_id: v.category_id, loan_id: v.loan_id,
          confidence: CategorizationDecision.confidences.fetch(v.confidence), reason: v.reason, guard: v.guard, created_at: now }
      end)
      applied = run.apply? && confident.any? ? apply(run, confident) : 0
      CategorizationRun.update_counters(run.id, confident_count: confident.size, unsure_count: result.verdicts.size - confident.size, applied_count: applied)
      run.add_usage!(result.usage)
    end
  end

  # Writes the confident verdicts through the same guards as the rake tasks (missing
  # categories only, booked only) and links their loans. Returns how many were written.
  def apply(run, verdicts)
    applied = BankTransactions::Categorization.apply(verdicts.to_h { |v| [ v.transaction_id, v.category_id ] }).applied
    loans = verdicts.select { |v| v.loan_id && applied.key?(v.transaction_id) }.to_h { |v| [ v.transaction_id, v.loan_id ] }
    BankTransactions::Categorization.link_loans(loans) if loans.any?
    run.decisions.where(bank_transaction_id: applied.keys).update_all(applied: true)
    applied.size
  end
end
