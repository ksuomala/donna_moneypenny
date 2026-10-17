namespace :transactions do
  desc "Print categories, accounts and known counterparty categories (read-only)"
  task categorization_context: :environment do
    puts BankTransactions::Categorization.context
  end

  desc "Print the oldest uncategorized booked transactions (read-only). LIMIT=200"
  task uncategorized: :environment do
    puts BankTransactions::Categorization.uncategorized(limit: Integer(ENV.fetch("LIMIT", "200")))
  end

  desc "Fill in missing categories. ASSIGN=\"transaction_id=category_id,...\" DRY_RUN=1 to preview"
  task categorize: :environment do
    dry_run = ENV["DRY_RUN"].present?
    result = BankTransactions::Categorization.apply(BankTransactions::Categorization.parse(ENV.fetch("ASSIGN")), dry_run: dry_run)
    names = TransactionCategory.where(id: result.applied.values).pluck(:id, :name).to_h

    puts "#{dry_run ? "Would categorize" : "Categorized"} #{result.applied.size} transactions"
    result.applied.values.tally.sort_by { |_, count| -count }.each { |id, count| puts "  #{count}\t#{names[id]}" }
    puts "Skipped (already categorized, pending or missing): #{result.skipped.join(", ")}" if result.skipped.any?
  end

  desc "Print Loans-category transactions not linked to a loan yet (read-only)"
  task unlinked_loans: :environment do
    puts BankTransactions::Categorization.unlinked_loan_transactions
  end

  desc "Link transactions to loans. ASSIGN=\"transaction_id=loan_id,...\" DRY_RUN=1 to preview"
  task link_loans: :environment do
    dry_run = ENV["DRY_RUN"].present?
    result = BankTransactions::Categorization.link_loans(BankTransactions::Categorization.parse(ENV.fetch("ASSIGN")), dry_run: dry_run)
    names = Loan.where(id: result.applied.values).pluck(:id, :name).to_h

    puts "#{dry_run ? "Would link" : "Linked"} #{result.applied.size} transactions"
    result.applied.values.tally.sort_by { |_, count| -count }.each { |id, count| puts "  #{count}\t#{names[id]}" }
    puts "Skipped (already linked, pending or missing): #{result.skipped.join(", ")}" if result.skipped.any?
  end
end

namespace :loans do
  desc "Print every loan with its balance today (read-only)"
  task list: :environment do
    Loan.order(:id).each do |loan|
      puts [ loan.id, loan.name, loan.creditor, loan.balance&.to_s("F") || "unknown", loan.currency ].join("\t")
    end
  end

  desc "Print a loan's recorded balances, oldest first (read-only). LOAN=id"
  task balances: :environment do
    loan = Loan.find(ENV.fetch("LOAN"))
    puts "# #{loan.name}: #{loan.balances.count} recorded balance(s)"
    puts "# on, balance, note"
    loan.balances.order(:on).each { |balance| puts [ balance.on, balance.balance.to_s("F"), balance.note ].join("\t") }
  end

  desc "Delete every recorded balance of a loan; its transactions stay. LOAN=id"
  task purge_balances: :environment do
    loan = Loan.find(ENV.fetch("LOAN"))
    puts "#{loan.name}: deleted #{loan.balances.delete_all} recorded balance(s)"
  end

  desc "Record a loan's balance on a day (replaces one recorded for the same day). LOAN=id ON=2026-10-01 BALANCE=1234.56 NOTE=..."
  task record_balance: :environment do
    loan = Loan.find(ENV.fetch("LOAN"))
    balance = loan.balances.find_or_initialize_by(on: Date.iso8601(ENV.fetch("ON")))
    balance.update!(balance: BigDecimal(ENV.fetch("BALANCE")), note: ENV["NOTE"])
    puts "#{loan.name}: #{balance.balance.to_s("F")} #{loan.currency} on #{balance.on}"
  end
end
