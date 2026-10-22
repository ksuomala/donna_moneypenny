module BankTransactions
  # A user's totals per category for a date range, split into incomes and expenses. With
  # several users (a household) the totals are combined: categories with the same name and
  # kind merge into one slice, and money that moved between the members (the same amount the
  # other way round on another member's account within a few days, e.g. rent paid to each
  # other) is left out of both sides.
  #
  # Expense and income categories show their totals as positive amounts (refunds reduce an
  # expense). Each investment sub-category is netted into one figure: rent 1000 minus vastike 280
  # is an income of 720, and an investment that cost more than it brought in shows as an expense. Uncategorized transactions count as "Uncategorized", money out as an
  # expense and money in as an income. Pending transactions are left out (every sync replaces
  # them), and so are categories excluded from stats.
  class Stats
    UNCATEGORIZED = "Uncategorized".freeze

    # kind is the category's kind (expense, income or investment), or uncategorized.
    Slice = Data.define(:name, :amount, :kind) do
      def investment? = kind == "investment"
      def uncategorized? = kind == "uncategorized"
    end

    # balance is what's owed at the end of the range and change how much that moved during it
    # (nil when we don't know the balance). taken is the money received from the loan in the
    # range and paid the payments made on it, both as positive amounts. limit is a credit
    # card's credit limit; loans have none.
    LoanRow = Data.define(:name, :creditor, :balance, :change, :taken, :paid, :limit) do
      def initialize(limit: nil, **attributes) = super
    end

    # balance is the account's balance at the end of the range and change how much it moved
    # during it (nil when we don't know).
    AccountRow = Data.define(:name, :balance, :change)

    # How far apart the two sides of a transfer between members may be booked, and how much
    # their amounts may differ (a transfer in another currency is converted at its own day's rate).
    TRANSFER_WINDOW = 5
    TRANSFER_TOLERANCE = BigDecimal("0.02")

    attr_reader :range, :users

    def initialize(range, user: nil, users: nil)
      @range = range
      @users = Array(users.presence || user)
      raise ArgumentError, "Stats need at least one user" if @users.empty?
    end

    def user = users.first
    def household? = users.many?

    # Slices are signed, so money in is income and money out an expense whatever the kind.
    def incomes
      slices.select { |slice| slice.amount.positive? }.sort_by { |slice| -slice.amount }
    end

    def expenses
      slices.select { |slice| slice.amount.negative? }.map { |slice| slice.with(amount: -slice.amount) }.sort_by { |slice| -slice.amount }
    end

    def income_total = incomes.sum(BigDecimal(0), &:amount)
    def expense_total = expenses.sum(BigDecimal(0), &:amount)
    def net = income_total - expense_total

    # Loans are excluded from income and expenses, so they get their own summary, which the
    # credit cards join. Paid-off loans with no money moving in the range are left out.
    def loans
      @loans ||= loan_rows + credit_card_rows
    end

    def loan_total = loans.filter_map(&:balance).sum(BigDecimal(0))
    def loans_taken = loans.sum(BigDecimal(0), &:taken)
    def loans_paid = loans.sum(BigDecimal(0), &:paid)

    # Current and savings accounts with the balance the bank last reported on or before the
    # end of the range.
    def accounts
      @accounts ||= BankAccount.owned_by(users).deposit.order(:id).map do |account|
        balance = account.balance_on(range.end)
        before = account.balance_on(range.begin - 1)
        AccountRow.new(name: account.display_name, balance:, change: (balance - before if balance && before))
      end
    end

    def account_total = accounts.filter_map(&:balance).sum(BigDecimal(0))

    # What moved between the members in the range and is left out: money out as a positive amount.
    def internal_transfers
      @internal_transfers ||= household? ? -all.where(id: internal_transfer_ids).where(amount: ...0).sum(:amount) : BigDecimal(0)
    end

    private

    def all
      BankTransaction.booked.where(occurred_on: range).where(bank_account_id: BankAccount.owned_by(users).select(:id))
    end

    def scope
      household? ? all.where.not(id: internal_transfer_ids) : all
    end

    # Transactions that have their other side on another member's account: the same amount
    # (within the tolerance) the other way round within the window, where each side names the
    # other member (the counterparty shares a name with the holder of the other member's
    # accounts, as the banks report it, that the holder of its own side does not have: a shared
    # surname names nobody in particular). Rows in categories left out of the stats don't pair:
    # they are out already and must not use up a partner. Each row pairs at most once.
    def internal_transfer_ids
      @internal_transfer_ids ||= begin
        rows_by_user = users.to_h do |u|
          [ u.id, countable.where(bank_account_id: u.bank_accounts.select(:id)).where.not(amount: 0).pluck(:id, :occurred_on, :amount, :counterparty_name) ]
        end
        holders = users.to_h { |u| [ u.id, holder_tokens(u) ] }
        paired = Set.new
        rows_by_user.each do |user_id, rows|
          others = rows_by_user.except(user_id).flat_map { |other_id, other_rows| other_rows.map { |row| [ other_id, *row ] } }
          rows.each do |id, on, amount, counterparty|
            next if paired.include?(id)

            match = others.find do |other_user_id, other_id, other_on, other_amount, other_counterparty|
              !paired.include?(other_id) && (other_on - on).abs <= TRANSFER_WINDOW &&
                (other_amount + amount).abs <= amount.abs * TRANSFER_TOLERANCE &&
                names?(counterparty, holders[other_user_id] - holders[user_id]) && names?(other_counterparty, holders[user_id] - holders[other_user_id])
            end
            paired << id << match[1] if match
          end
        end
        paired.to_a
      end
    end

    # The rows that count in the stats: uncategorized or in a category that isn't excluded.
    def countable
      all.left_joins(:transaction_category).where(transaction_categories: { id: nil }).or(all.left_joins(:transaction_category).merge(TransactionCategory.in_stats))
    end

    # The words of the account holder names the banks report for a user's accounts.
    def holder_tokens(user)
      user.bank_accounts.filter_map { |account| account.raw&.dig("name") }.flat_map { |name| name_tokens(name) }.to_set
    end

    def names?(counterparty, tokens)
      counterparty.present? && tokens.intersect?(name_tokens(counterparty))
    end

    def name_tokens(name)
      name.to_s.downcase.scan(/[[:alpha:]]{3,}/)
    end

    def slices
      @slices ||= category_slices + uncategorized_slices
    end

    # Net sum per category, keeping only the sides that make sense for its kind: an expense
    # category that comes out positive (more refunds than spending) is dropped, likewise an
    # income category that comes out negative.
    def category_slices
      sums = scope.joins(:transaction_category).merge(TransactionCategory.in_stats)
        .group(:transaction_category_id).sum(:amount)
      categories = TransactionCategory.where(id: sums.keys).index_by(&:id)

      # Members' categories with the same name and kind are one slice.
      merged = sums.each_with_object(Hash.new(BigDecimal(0))) do |(category_id, amount), totals|
        category = categories[category_id]
        totals[[ category.name, category.kind ]] += amount
      end

      merged.filter_map do |(name, kind), amount|
        next if amount.zero?
        next if kind == "expense" && amount.positive?
        next if kind == "income" && amount.negative?

        Slice.new(name:, amount:, kind:)
      end
    end

    # Not netted: money in and money out are unrelated until they're categorized.
    def uncategorized_slices
      uncategorized = scope.where(transaction_category_id: nil)
      [ uncategorized.where(amount: ...0), uncategorized.where(amount: 0.01..) ].filter_map do |side|
        amount = side.sum(:amount)
        Slice.new(name: UNCATEGORIZED, amount:, kind: "uncategorized") unless amount.zero?
      end
    end

    def loan_rows
      Loan.where(user: users).order(:name).filter_map do |loan|
        balance = loan.balance_on(range.end)
        before = loan.balance_on(range.begin - 1)
        moved = loan.bank_transactions.booked.where(occurred_on: range)
        taken = moved.where(amount: 0.01..).sum(:amount)
        paid = -moved.where(amount: ...0).sum(:amount)
        next if balance&.zero? && taken.zero? && paid.zero?

        LoanRow.new(name: loan.name, creditor: loan.creditor, balance:, change: (balance - before if balance && before), taken:, paid:)
      end
    end

    # A credit card is listed with what's owed on it and how that changed over the range. Its
    # purchases are already in the expenses and payments onto it are Own, so it has no taken
    # and paid. A card with nothing owed and nothing moving in the range is left out.
    def credit_card_rows
      BankAccount.owned_by(users).where(type: CreditCard.sti_name).order(:id).filter_map do |card|
        balance = card.owed_on(range.end)
        before = card.owed_on(range.begin - 1)
        next if balance&.zero? && card.bank_transactions.booked.where(occurred_on: range).none?

        LoanRow.new(name: card.display_name, creditor: card.creditor, balance:, change: (balance - before if balance && before),
                    taken: 0, paid: 0, limit: card.credit_limit)
      end
    end
  end
end
