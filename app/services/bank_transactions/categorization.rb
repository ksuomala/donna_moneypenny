module BankTransactions
  # Read and write side of categorizing transactions and linking them to loans, used by the
  # categorize-transactions skill through the transactions:* rake tasks. Output is tab-separated
  # to keep it compact.
  #
  # Writes only ever fill in what's missing: a transaction that already has a category or loan
  # (set by hand or in an earlier run) is left alone. Pending transactions are skipped because
  # every sync replaces them.
  class Categorization
    Result = Data.define(:applied, :skipped)

    # Categories with their instructions, plus how counterparties have been categorized so far,
    # so later runs stay consistent with earlier ones. excluding: transaction ids whose
    # decisions are left out (the categorizer's evaluation hides the transactions it tests).
    def self.context(excluding: [])
      lines = [ "# categories: id, name, kind, parent, description" ]
      TransactionCategory.includes(:parent, :children).order(:id).each do |category|
        next if category.children.any?

        kind = category.exclude_from_stats? ? "excluded" : category.kind
        lines << row(category.id, category.name, kind, category.parent&.name, category.description)
      end

      lines << "" << "# loans: id, name, creditor, balance follows transactions, description"
      Loan.order(:id).each do |loan|
        lines << row(loan.id, loan.name, loan.creditor, loan.balance_from_transactions? ? "yes" : "no", loan.description)
      end

      lines << "" << "# accounts: id, name, kind"
      BankAccount.order(:id).each { |account| lines << row(account.id, account.display_name, account.credit_card? ? "credit card" : "account") }

      lines << "" << "# known counterparties: counterparty, account id, category, count"
      names = TransactionCategory.pluck(:id, :name).to_h
      known_decisions(excluding: excluding).each do |name, account_id, category_id, count|
        lines << row(name, account_id, names[category_id], count)
      end

      lines.join("\n")
    end

    # How counterparties have been categorized so far: [counterparty, account id, category id,
    # count], most frequent first.
    def self.known_decisions(excluding: [])
      scope = BankTransaction.where.not(transaction_category_id: nil).where.not(counterparty_name: nil)
      scope = scope.where.not(id: excluding) if excluding.any?
      scope.group(:counterparty_name, :bank_account_id, :transaction_category_id).order(Arel.sql("COUNT(*) DESC"))
        .pluck(:counterparty_name, :bank_account_id, :transaction_category_id, Arel.sql("COUNT(*)"))
    end

    # For each transaction, up to five rows on other accounts with the same amount the other way
    # round within five days: the candidates for the other side of an own transfer or a credit
    # card payment. Pending rows count, since the other side is often still pending. Returns
    # transaction id => rows; hide lists ids whose category the caller must not show.
    PAIR_WINDOW = 5
    def self.pairing_hints(transactions, hide: [])
      transactions.to_h do |t|
        others = BankTransaction.where.not(bank_account_id: t.bank_account_id).where(amount: -t.amount)
          .where(occurred_on: (t.occurred_on - PAIR_WINDOW)..(t.occurred_on + PAIR_WINDOW)).order(:occurred_on, :id).limit(5).to_a
        [ t.id, others ]
      end
    end

    # One transaction as the tab-separated line the listings and the categorizer use.
    def self.transaction_row(t)
      row(t.id, t.bank_account_id, t.occurred_on, t.amount.to_s("F"), t.currency, t.counterparty_name,
          t.description, t.reference_number, t.merchant_category_code, t.raw&.dig("bank_transaction_code", "description"))
    end

    # The oldest uncategorized booked transactions.
    def self.uncategorized(limit: 200)
      scope = BankTransaction.booked.where(transaction_category_id: nil)
      lines = [ "# uncategorized: #{scope.count} total, showing #{[ limit, scope.count ].min}",
                "# id, account id, date, amount, currency, counterparty, description, reference, mcc, bank code" ]

      scope.order(:occurred_on, :id).limit(limit).each { |t| lines << transaction_row(t) }

      lines.join("\n")
    end

    # Transactions in the Loans category that aren't linked to a loan yet, with the loans that
    # earlier transactions from the same counterparty and reference were linked to. Interest
    # and fees on a credit card are Loans too but belong to the card, not to a loan, so credit
    # card accounts are left out.
    def self.unlinked_loan_transactions
      scope = BankTransaction.booked.joins(:transaction_category, :bank_account).merge(BankAccount.deposit)
        .where(transaction_categories: { name: "Loans" }, loan_id: nil)
      lines = [ "# unlinked loan transactions: #{scope.count}",
                "# id, account id, date, amount, counterparty, description, reference, bank code" ]
      scope.order(:occurred_on, :id).each do |t|
        lines << row(t.id, t.bank_account_id, t.occurred_on, t.amount.to_s("F"), t.counterparty_name, t.description,
                     t.reference_number, t.raw&.dig("bank_transaction_code", "description"))
      end

      lines << "" << "# linked so far: loan, account id, counterparty, count"
      BankTransaction.where.not(loan_id: nil).joins(:loan).group("loans.name", :bank_account_id, :counterparty_name)
        .order(Arel.sql("COUNT(*) DESC")).pluck("loans.name", :bank_account_id, :counterparty_name, Arel.sql("COUNT(*)"))
        .each { |values| lines << row(*values) }

      lines.join("\n")
    end

    # Takes "transaction_id=category_id" (or "transaction_id=loan_id") pairs separated by commas or spaces.
    def self.parse(assignments)
      assignments.to_s.split(/[\s,]+/).compact_blank.to_h do |pair|
        transaction_id, category_id = pair.split("=", 2).map { |id| Integer(id, exception: false) }
        raise ArgumentError, "Bad assignment #{pair.inspect}, expected transaction_id=category_id" unless transaction_id && category_id

        [ transaction_id, category_id ]
      end
    end

    def self.apply(assignments, dry_run: false)
      categories = TransactionCategory.where(id: assignments.values.uniq).includes(:children).index_by(&:id)
      invalid = assignments.values.uniq.reject { |id| categories[id] && categories[id].children.empty? }
      raise ArgumentError, "Unknown or parent categories: #{invalid.join(", ")}" if invalid.any?

      eligible = BankTransaction.booked.where(id: assignments.keys, transaction_category_id: nil).pluck(:id).to_set
      applied, skipped = assignments.partition { |transaction_id, _| eligible.include?(transaction_id) }

      unless dry_run
        BankTransaction.transaction do
          applied.group_by(&:last).each do |category_id, pairs|
            BankTransaction.where(id: pairs.map(&:first), transaction_category_id: nil).update_all(transaction_category_id: category_id, updated_at: Time.current)
          end
        end
      end

      Result.new(applied: applied.to_h, skipped: skipped.to_h.keys)
    end

    def self.link_loans(assignments, dry_run: false)
      unknown = assignments.values.uniq - Loan.where(id: assignments.values.uniq).pluck(:id)
      raise ArgumentError, "Unknown loans: #{unknown.join(", ")}" if unknown.any?

      eligible = BankTransaction.booked.where(id: assignments.keys, loan_id: nil).pluck(:id).to_set
      applied, skipped = assignments.partition { |transaction_id, _| eligible.include?(transaction_id) }

      unless dry_run
        BankTransaction.transaction do
          applied.group_by(&:last).each do |loan_id, pairs|
            BankTransaction.where(id: pairs.map(&:first), loan_id: nil).update_all(loan_id: loan_id, updated_at: Time.current)
          end
        end
      end

      Result.new(applied: applied.to_h, skipped: skipped.to_h.keys)
    end

    def self.row(*values)
      values.map { |value| value.to_s.squish }.join("\t")
    end
  end
end
