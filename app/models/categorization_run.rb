# One pass of the categorizer over a set of transactions (CategorizeTransactionsJob), with its
# decisions, token usage and outcome. shadow runs only store decisions, apply runs also write
# the confident ones to the transactions, eval runs test the categorizer on transactions that
# already have a category (transactions:categorizer_eval).
class CategorizationRun < ApplicationRecord
  has_many :decisions, class_name: "CategorizationDecision", dependent: :delete_all

  enum :mode, { shadow: 0, apply: 1, eval: 2 }

  # USD per million tokens, for the estimate in transactions:categorizer_runs.
  PRICES = {
    "claude-opus-5-5" => { input: 4.0, output: 20.0, cache_read: 0.20, cache_write: 5.0 },
    "claude-sonnet-5-5" => { input: 2.0, output: 10.0, cache_read: 0.20, cache_write: 2.5 },
    "claude-haiku-4-5" => { input: 1.0, output: 5.0, cache_read: 0.10, cache_write: 1.25 }
  }.freeze

  scope :latest_first, -> { order(id: :desc) }

  def finished? = finished_at.present?

  # Estimated cost in USD, or nil for a model without a known price.
  def cost
    prices = PRICES.find { |name, _| model.start_with?(name) }&.last
    return unless prices

    (input_tokens * prices[:input] + output_tokens * prices[:output] +
     cache_read_input_tokens * prices[:cache_read] + cache_creation_input_tokens * prices[:cache_write]) / 1_000_000
  end

  def add_usage!(usage)
    self.class.update_counters(id, input_tokens: usage.input_tokens, output_tokens: usage.output_tokens,
                                   cache_read_input_tokens: usage.cache_read_input_tokens, cache_creation_input_tokens: usage.cache_creation_input_tokens)
    reload
  end

  # The unsure decisions as the table the categorize-transactions skill works from, grouped by
  # counterparty: id, account id, date, amount, counterparty, description, guess, loan, reason, guard.
  def unsure_lines
    lines = [ "# run #{id} (#{mode}, #{started_at.to_date}): #{unsure_count} unsure of #{transactions_count}",
              "# id, account id, date, amount, counterparty, description, guessed category, guessed loan, reason, guard" ]
    decisions.unsure.includes(:bank_transaction, :transaction_category, :loan)
      .sort_by { |d| [ d.bank_transaction.counterparty_name.to_s.downcase, d.bank_transaction.occurred_on, d.bank_transaction_id ] }
      .each do |d|
        t = d.bank_transaction
        lines << [ t.id, t.bank_account_id, t.occurred_on, t.amount.to_s("F"), t.counterparty_name, t.description,
                   d.transaction_category&.name, d.loan&.name, d.reason, d.guard ].map { |v| v.to_s.squish }.join("\t")
      end
    lines.join("\n")
  end

  # The latest runs: id, mode, started, finished, transactions, confident, unsure, applied, tokens in/out/cached, cost, error.
  def self.summary_lines(limit: 20)
    lines = [ "# id, mode, model, started, finished, transactions, confident, unsure, applied, input tokens, output tokens, cache reads, cost USD, error" ]
    latest_first.limit(limit).each do |run|
      lines << [ run.id, run.mode, run.model, run.started_at&.strftime("%F %R"), run.finished_at&.strftime("%F %R") || "running", run.transactions_count,
                 run.confident_count, run.unsure_count, run.applied_count, run.input_tokens, run.output_tokens, run.cache_read_input_tokens,
                 run.cost&.round(3), run.error&.first(80) ].map { |v| v.to_s.squish }.join("\t")
    end
    lines.join("\n")
  end
end
