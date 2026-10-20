module BankTransactions
  # Deterministic categorization before the model: CategorizationRule records matched on the
  # reference (plus account, counterparty, direction when set). Runs on every sync, in this order:
  # retire! switches off rules the owner's own categorizations contradict, derive! creates rules
  # from references used consistently, apply! fills in categories (and loans) from active rules.
  # Like every write here, it only fills in what's missing.
  class Rules
    MIN_MATCHES = 3
    MIN_REFERENCE = 6
    Applied = Data.define(:categorized, :linked)

    # Retires, derives and applies. Returns { retired:, derived:, applied: }.
    def self.refresh!
      { retired: retire!, derived: derive!, applied: apply! }
    end

    # Fills in the category, and the loan where missing, of uncategorized booked transactions
    # that an active rule matches. The first matching rule (manual before derived) wins.
    # Returns rule => count; dry_run counts without writing.
    def self.apply!(dry_run: false)
      rules = CategorizationRule.active.in_order.includes(:transaction_category).to_a
      return Applied.new({}, 0) if rules.empty?

      categorized = Hash.new(0)
      linked = 0
      BankTransaction.booked.where(transaction_category_id: nil).find_each do |t|
        rule = rules.find { |r| r.matches?(t) } or next
        categorized[rule] += 1
        linked += 1 if rule.loan_id && t.loan_id.nil?
        next if dry_run

        BankTransaction.where(id: t.id, transaction_category_id: nil)
          .update_all(transaction_category_id: rule.transaction_category_id, categorization_rule_id: rule.id, updated_at: Time.current)
        BankTransaction.where(id: t.id, loan_id: nil).update_all(loan_id: rule.loan_id) if rule.loan_id
      end
      Applied.new(categorized.to_h, linked)
    end

    # Creates rules from the owner's history, for references and for counterparty + exact amount
    # pairs that appear on at least MIN_MATCHES categorized booked transactions, all with the same
    # category and loan, and that no rule (active or retired) covers yet. The account is kept when
    # all of them are on one account. Returns the rules.
    def self.derive!(dry_run: false)
      by_reference = derive_by_reference(dry_run)
      by_reference + derive_by_amount(dry_run, by_reference)
    end

    def self.derive_by_reference(dry_run)
      covered = CategorizationRule.pluck(:reference).compact.to_set
      prefixes = CategorizationRule.active.pluck(:reference_prefix).compact
      groups = BankTransaction.booked.where.not(transaction_category_id: nil).where.not(reference_number: [ nil, "" ])
        .pluck(:reference_number, :transaction_category_id, :loan_id, :bank_account_id)
        .group_by { |ref, *| CategorizationRule.normalize_reference(ref) }

      groups.filter_map do |ref, rows|
        next if ref.nil? || ref.length < MIN_REFERENCE || rows.size < MIN_MATCHES
        next if covered.include?(ref) || prefixes.any? { |prefix| ref.start_with?(prefix) }
        next unless rows.map { |_, category_id, loan_id, _| [ category_id, loan_id ] }.uniq.one?

        _, category_id, loan_id, = rows.first
        accounts = rows.map(&:last).uniq
        rule = CategorizationRule.new(reference: ref, transaction_category_id: category_id, loan_id: loan_id,
                                      bank_account_id: (accounts.first if accounts.one?), source: :derived,
                                      note: "derived from #{rows.size} transactions on #{Date.current}")
        next unless rule.valid?

        rule.save! unless dry_run
        rule
      end
    end

    # The same amount to or from the same counterparty, e.g. rent or a loan installment. Skipped
    # when a reference rule already covers those transactions.
    def self.derive_by_amount(dry_run, new_reference_rules)
      covered = CategorizationRule.where.not(counterparty: nil).where.not(amount: nil).pluck(:counterparty, :amount).map { |c, a| [ c.downcase, a ] }.to_set
      reference_rules = (CategorizationRule.active.where(counterparty: nil, amount: nil).to_a + new_reference_rules).uniq
      groups = BankTransaction.booked.where.not(transaction_category_id: nil).where.not(counterparty_name: [ nil, "" ]).to_a
        .group_by { |t| [ t.counterparty_name.squish.downcase, t.amount ] }

      groups.filter_map do |(name, amount), rows|
        next if rows.size < MIN_MATCHES || covered.include?([ name, amount ])
        next if rows.all? { |t| reference_rules.any? { |r| r.matches?(t) } }
        next unless rows.map { |t| [ t.transaction_category_id, t.loan_id ] }.uniq.one?

        accounts = rows.map(&:bank_account_id).uniq
        rule = CategorizationRule.new(counterparty: rows.first.counterparty_name.squish, amount: amount,
                                      transaction_category_id: rows.first.transaction_category_id, loan_id: rows.first.loan_id,
                                      bank_account_id: (accounts.first if accounts.one?), source: :derived,
                                      note: "derived from #{rows.size} transactions on #{Date.current}")
        next unless rule.valid?

        rule.save! unless dry_run
        rule
      end
    end
    private_class_method :derive_by_reference, :derive_by_amount

    # Switches off every active rule that a categorized transaction contradicts: it matches the
    # rule but has another category, or another loan where both have one. Returns the rules.
    def self.retire!(dry_run: false)
      CategorizationRule.active.includes(:transaction_category).filter_map do |rule|
        conflicts = conflicts(rule)
        next if conflicts.empty?

        rule.disable!("#{conflicts.size} transaction(s) categorized otherwise, e.g. #{conflicts.first.id}") unless dry_run
        rule
      end
    end

    # The categorized booked transactions that match a rule but disagree with it.
    def self.conflicts(rule)
      candidates(rule).where.not(transaction_category_id: nil).select do |t|
        rule.matches?(t) &&
          (t.transaction_category_id != rule.transaction_category_id || (rule.loan_id && t.loan_id && t.loan_id != rule.loan_id))
      end
    end

    # Matching categorized transactions: [agreeing, conflicting].
    def self.check(rule)
      matching = candidates(rule).where.not(transaction_category_id: nil).select { |t| rule.matches?(t) }
      [ matching.size - conflicts(rule).size, conflicts(rule).size ]
    end

    def self.candidates(rule)
      scope = BankTransaction.booked
      scope = scope.where(bank_account_id: rule.bank_account_id) if rule.bank_account_id
      return scope.where(amount: rule.amount).where("LOWER(counterparty_name) = ?", rule.counterparty.downcase) if rule.amount && rule.counterparty

      key = rule.reference || rule.reference_prefix
      scope.where("REPLACE(reference_number, ' ', '') LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(key)}%")
    end
    private_class_method :candidates
  end
end
