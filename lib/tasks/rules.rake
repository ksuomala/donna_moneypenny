namespace :rules do
  desc "Print every categorization rule with its matches and conflicts (read-only)"
  task list: :environment do
    puts "# id, active, source, conditions, category, loan, agreeing, conflicting, set by it, note / disabled reason"
    CategorizationRule.includes(:transaction_category, :loan).in_order.each do |rule|
      agreeing, conflicting = BankTransactions::Rules.check(rule)
      puts [ rule.id, rule.active? ? "active" : "off", rule.source, rule.describe, rule.transaction_category.name, rule.loan&.name,
             agreeing, conflicting, rule.bank_transactions.count, rule.disabled_reason || rule.note ].map { |v| v.to_s.squish }.join("\t")
    end
  end

  desc "Create rules from references, and from the same amount to the same counterparty, used consistently in the history (3+ times, one category and loan). DRY_RUN=1 to preview"
  task derive: :environment do
    dry_run = ENV["DRY_RUN"].present?
    rules = BankTransactions::Rules.derive!(dry_run: dry_run)
    puts "#{dry_run ? "Would create" : "Created"} #{rules.size} rules"
    rules.each { |r| puts [ r.describe, r.transaction_category.name, r.loan&.name, r.note ].map { |v| v.to_s.squish }.join("\t") }
  end

  desc "Fill in categories from active rules, as after every sync. DRY_RUN=1 to preview"
  task apply: :environment do
    dry_run = ENV["DRY_RUN"].present?
    result = BankTransactions::Rules.apply!(dry_run: dry_run)
    puts "#{dry_run ? "Would categorize" : "Categorized"} #{result.categorized.values.sum} transactions, #{dry_run ? "would link" : "linked"} #{result.linked} to a loan"
    result.categorized.each { |rule, count| puts "  #{count}\t#{rule.describe}\t#{rule.transaction_category.name}" }
  end

  desc "Switch off rules that categorized transactions contradict. DRY_RUN=1 to preview"
  task retire: :environment do
    dry_run = ENV["DRY_RUN"].present?
    rules = BankTransactions::Rules.retire!(dry_run: dry_run)
    puts "#{dry_run ? "Would retire" : "Retired"} #{rules.size} rules"
    rules.each { |r| puts "  #{r.id}\t#{r.describe}\t#{r.transaction_category.name}" }
  end

  desc "Create a manual rule, or update one with the same conditions. CATEGORY=... LOAN=name REFERENCE=... or PREFIX=... or COUNTERPARTY=... AMOUNT=-2000.00; ACCOUNT=id DIRECTION=incoming|outgoing NOTE=..."
  task upsert: :environment do
    conditions = { reference: CategorizationRule.normalize_reference(ENV["REFERENCE"]), reference_prefix: CategorizationRule.normalize_reference(ENV["PREFIX"]),
                   bank_account_id: ENV["ACCOUNT"].presence&.to_i, counterparty: ENV["COUNTERPARTY"].presence&.squish, direction: ENV["DIRECTION"].presence,
                   amount: ENV["AMOUNT"].presence && BigDecimal(ENV["AMOUNT"]) }
    rule = CategorizationRule.find_or_initialize_by(conditions.merge(source: :manual))
    rule.transaction_category = TransactionCategory.find_by!(name: ENV.fetch("CATEGORY"))
    rule.loan = ENV["LOAN"].present? ? Loan.find_by!(name: ENV["LOAN"]) : nil
    rule.note = ENV["NOTE"] if ENV["NOTE"]
    rule.active = true
    rule.disabled_reason = nil
    rule.save!
    agreeing, conflicting = BankTransactions::Rules.check(rule)
    puts [ rule.previously_new_record? ? "Created" : "Updated", rule.id, rule.describe, rule.transaction_category.name, rule.loan&.name ].compact.join("\t")
    puts "Matches #{agreeing} categorized transactions that agree, #{conflicting} that don't#{" (it will be retired on the next sync unless those are fixed)" if conflicting.positive?}"
  end

  desc "Switch a rule off (ID=...) or back on (ID=... ON=1)"
  task toggle: :environment do
    rule = CategorizationRule.find(ENV.fetch("ID"))
    ENV["ON"].present? ? rule.update!(active: true, disabled_reason: nil) : rule.disable!("switched off by hand")
    puts "#{rule.id}\t#{rule.active? ? "active" : "off"}\t#{rule.describe}"
  end
end
