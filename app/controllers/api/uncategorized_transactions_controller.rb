module Api
  # Booked transactions still without a category, oldest first, with the categorizer's guess:
  # what Telegram::UncategorizedNotice lists. Reading them doesn't mark them listed.
  class UncategorizedTransactionsController < BaseController
    MAX_LIMIT = 200

    def index
      scope = Telegram::UncategorizedNotice.new(Current.user).uncategorized
      transactions = scope.includes(:bank_account).order(:occurred_on, :id).limit(limit).to_a
      guesses = CategorizationDecision.where(bank_transaction_id: transactions.map(&:id)).order(:id)
        .includes(:transaction_category).index_by(&:bank_transaction_id)

      render json: {
        total: scope.count,
        transactions: transactions.map do |transaction|
          guess = guesses[transaction.id]&.transaction_category
          transaction_json(transaction).merge(account: transaction.bank_account.display_name, notified_at: transaction.uncategorized_notified_at,
                                              guess: guess && { category_id: guess.id, name: guess.name })
        end
      }
    end

    private

    def limit = params[:limit].present? ? Integer(params[:limit]).clamp(1, MAX_LIMIT) : 50
  end
end
