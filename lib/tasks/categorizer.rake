namespace :transactions do
  desc "Run the categorizer over the uncategorized backlog now, in the background (shadow unless CATEGORIZER_APPLY). LIMIT=200. DRY_RUN=1 decides one batch inline and stores nothing"
  task categorizer_run: :environment do
    config = Rails.configuration.x.categorizer
    abort "No Anthropic API key: add anthropic.api_key with bin/rails credentials:edit, or set ANTHROPIC_API_KEY" unless BankTransactions::Categorizer.configured?

    if ENV["DRY_RUN"].present?
      batch = BankTransaction.booked.where(transaction_category_id: nil).order(:occurred_on, :id).limit(Integer(ENV.fetch("LIMIT", config.batch_size.to_s))).to_a
      abort "Nothing to categorize" if batch.empty?

      result = BankTransactions::Categorizer.new.call(batch)
      names = TransactionCategory.pluck(:id, :name).to_h
      loans = Loan.pluck(:id, :name).to_h
      puts "# dry run with #{result.model}: #{result.verdicts.count(&:confident?)} confident, #{result.verdicts.count { |v| !v.confident? }} unsure, nothing stored"
      puts "# id, date, amount, counterparty, description, confidence, category, loan, reason, guard"
      batch.zip(result.verdicts).each do |t, v|
        puts [ t.id, t.occurred_on, t.amount.to_s("F"), t.counterparty_name, t.description, v.confidence, names[v.category_id], loans[v.loan_id], v.reason, v.guard ]
          .map { |value| value.to_s.squish }.join("\t")
      end
      puts "# tokens: #{result.usage.input_tokens} in, #{result.usage.output_tokens} out, #{result.usage.cache_read_input_tokens} read from cache"
    else
      CategorizeTransactionsJob.perform_later(limit: ENV["LIMIT"]&.to_i)
      puts "Enqueued a #{config.apply ? "apply" : "shadow"} run; follow it with transactions:categorizer_runs"
    end
  end

  desc "Print the unsure decisions of the latest run (or RUN=id), grouped by counterparty, for the categorize-transactions skill (read-only)"
  task unsure: :environment do
    run = ENV["RUN"].present? ? CategorizationRun.find(ENV["RUN"]) : CategorizationRun.where.not(mode: :eval).latest_first.first
    abort "No categorizer runs yet" unless run

    puts run.unsure_lines
  end

  desc "Print the categorizer runs with their counts, token usage and estimated cost (read-only). LIMIT=20"
  task categorizer_runs: :environment do
    puts CategorizationRun.summary_lines(limit: Integer(ENV.fetch("LIMIT", "20")))
  end
end

namespace :transactions do
  desc "Test the categorizer on already categorized transactions sent as new; writes nothing to them. SAMPLE=200 SINCE=2026-01-01"
  task categorizer_eval: :environment do
    abort "No Anthropic API key: add anthropic.api_key with bin/rails credentials:edit, or set ANTHROPIC_API_KEY" unless BankTransactions::Categorizer.configured?

    since = ENV["SINCE"].present? ? Date.iso8601(ENV["SINCE"]) : nil
    puts BankTransactions::CategorizerEval.new(sample: Integer(ENV.fetch("SAMPLE", "200")), since: since).call.report
  end
end
