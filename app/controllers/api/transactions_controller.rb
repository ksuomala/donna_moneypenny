module Api
  # Adds a transaction to one of the user's manual accounts (cash), like bin/rails
  # transactions:create. Money out is negative. Bank accounts get theirs from the sync only.
  class TransactionsController < BaseController
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
