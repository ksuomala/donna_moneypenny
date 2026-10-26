# Decides categories for the uncategorized booked transactions with a model
# (BankTransactions::Categorizer; GPT-6 Luna by default, see config/initializers/categorizer.rb),
# one batch per job: Solid Queue runs inside Puma and gets seconds on a restart, so no job may run
# for minutes. Every user gets a run of their own, built from their own categories, loans,
# accounts and earlier decisions: enqueued without arguments (after every sync) the job fans out
# into one job per user with categories. The first job of a run picks the user's transactions and
# creates the CategorizationRun; every job decides one batch, stores the decisions, applies the
# confident ones when the categorizer is in apply mode, and enqueues the next batch. Once a
# user's run is through (or there is no categorizer), the budget alerts are checked.
class CategorizeTransactionsJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "categorizer"

  RATE_LIMIT_WAIT = 5.minutes

  # Without arguments: a run for every user with categories. user_id starts one user's run;
  # run_id and ids continue a run with what's left of it. limit caps a new run (default
  # max_per_run); batch_size shrinks after a truncated answer.
  def perform(user_id: nil, run_id: nil, ids: nil, limit: nil, batch_size: nil)
    unless BankTransactions::Categorizer.configured?
      Rails.logger.info("[categorizer] no API key for #{config.model} (see bin/rails credentials:edit), skipping")
      ReportsJob.perform_later if run_id.nil? && user_id.nil?
      return
    end
    if run_id.nil? && user_id.nil?
      User.categorizing.each { |user| self.class.perform_later(user_id: user.id, limit: limit) }
      return
    end

    run, ids = run_id ? [ CategorizationRun.find(run_id), ids ] : start(User.find(user_id), limit: limit)
    return ReportsJob.perform_later if run.finished?

    batch_size ||= config.batch_size
    batch, rest = ids.first(batch_size), ids.drop(batch_size)
    decide(run, batch)
    if rest.any?
      self.class.perform_later(run_id: run.id, ids: rest, batch_size: batch_size)
    else
      run.update!(finished_at: Time.current)
      ReportsJob.perform_later
    end
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

  # A new run over the user's oldest uncategorized booked transactions, leaving out the ones the
  # same model decided for this user recently under the same rules (a changed category
  # description or another model lifts the cooldown).
  def start(user, limit:)
    cooled = CategorizationDecision.joins(:run).where(created_at: config.cooldown_days.days.ago..)
      .merge(CategorizationRun.where(user: user, rules_digest: BankTransactions::Categorizer.rules_digest(user), model: config.model, mode: [ :shadow, :apply ]))
      .select(:bank_transaction_id)
    ids = user.bank_transactions.booked.where(transaction_category_id: nil).where.not(id: cooled).order(:occurred_on, :id).limit(limit || config.max_per_run).pluck(:id)
    run = CategorizationRun.create!(user: user, mode: config.apply ? :apply : :shadow, model: config.model, prompt_version: BankTransactions::Categorizer.prompt_version,
                                    rules_digest: BankTransactions::Categorizer.rules_digest(user), started_at: Time.current,
                                    transactions_count: ids.size, finished_at: (Time.current if ids.empty?))
    [ run, ids ]
  end

  def decide(run, ids)
    transactions = run.user.bank_transactions.booked.where(id: ids, transaction_category_id: nil).order(:occurred_on, :id).to_a
    return if transactions.empty?

    result = BankTransactions::Categorizer.new(model: run.model, user: run.user).call(transactions)
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
  # categories only, booked only, the user's own categories and loans) and links their loans.
  # Returns how many were written.
  def apply(run, verdicts)
    applied = BankTransactions::Categorization.apply(verdicts.to_h { |v| [ v.transaction_id, v.category_id ] }, user: run.user).applied
    loans = verdicts.select { |v| v.loan_id && applied.key?(v.transaction_id) }.to_h { |v| [ v.transaction_id, v.loan_id ] }
    BankTransactions::Categorization.link_loans(loans, user: run.user) if loans.any?
    run.decisions.where(bank_transaction_id: applied.keys).update_all(applied: true)
    applied.size
  end
end
