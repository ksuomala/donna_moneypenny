module BankTransactions
  # A user's totals per category for a date range, split into incomes and expenses.
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

    attr_reader :range, :user

    def initialize(range, user:)
      @range = range
      @user = user
    end

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
      @accounts ||= user.bank_accounts.deposit.order(:id).map do |account|
        balance = account.balance_on(range.end)
        before = account.balance_on(range.begin - 1)
        AccountRow.new(name: account.display_name, balance:, change: (balance - before if balance && before))
      end
    end

    def account_total = accounts.filter_map(&:balance).sum(BigDecimal(0))

    private

    def scope
      user.bank_transactions.booked.where(occurred_on: range)
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

      sums.filter_map do |category_id, amount|
        category = categories[category_id]
        next if amount.zero?
        next if category.expense? && amount.positive?
        next if category.income? && amount.negative?

        Slice.new(name: category.name, amount:, kind: category.kind)
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
      user.loans.order(:name).filter_map do |loan|
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
      user.bank_accounts.where(type: CreditCard.sti_name).order(:id).filter_map do |card|
        balance = card.owed_on(range.end)
        before = card.owed_on(range.begin - 1)
        next if balance&.zero? && card.bank_transactions.booked.where(occurred_on: range).none?

        LoanRow.new(name: card.display_name, creditor: card.creditor, balance:, change: (balance - before if balance && before),
                    taken: 0, paid: 0, limit: card.credit_limit)
      end
    end
  end
end
