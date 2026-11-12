module Api
  # The user's transactions, and adding one to a manual account.
  class TransactionsController < BaseController
    # Every transaction of the user's accounts in a date range (from and to included), oldest
    # first, with its account and category. Pending ones are included with their status: every
    # sync replaces them.
    def index
      range = date_range
      transactions = BankTransaction.where(bank_account: Current.user.bank_accounts, occurred_on: range)
        .includes(:bank_account, transaction_category: :parent).order(:occurred_on, :id)

      render json: {
        from: range.begin,
        to: range.end,
        transactions: transactions.map do |transaction|
          category = transaction.transaction_category
          transaction_json(transaction).merge(
            account: transaction.bank_account.display_name, status: transaction.status, bank_code: transaction.bank_code,
            category: category && { id: category.id, name: category.name, parent: category.parent&.name,
                                    kind: category.exclude_from_stats? ? "excluded" : category.kind }
          )
        end
      }
    end

    # Adds a transaction to one of the user's manual accounts (cash), like bin/rails
    # transactions:create. Money out is negative. Bank accounts get theirs from the sync only.
    def create
      account = ManualAccount.where(user: Current.user).find(params.require(:account_id))
      category = Current.user.transaction_categories.find(params[:category_id]) if params[:category_id].present?
      transaction = account.record!(on: Date.iso8601(params.require(:date)), amount: BigDecimal(params.require(:amount).to_s),
                                    counterparty: params[:counterparty], description: params[:description],
                                    category: category, dry_run: dry_run?)

      render json: transaction_json(transaction).merge(dry_run: dry_run?), status: dry_run? ? :ok : :created
    end
  end
end
