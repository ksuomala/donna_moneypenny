module Api
  # Fills in categories on uncategorized transactions, like bin/rails transactions:categorize:
  # a transaction that already has a category, a pending one or another user's is skipped.
  class CategorizationsController < BaseController
    def create
      assignments = params.expect(assignments: [ %i[transaction_id category_id] ]).to_h do |assignment|
        [ Integer(assignment.fetch(:transaction_id)), Integer(assignment.fetch(:category_id)) ]
      end
      result = BankTransactions::Categorization.apply(assignments, dry_run: dry_run?, user: Current.user)

      render json: {
        dry_run: dry_run?,
        applied: result.applied.map { |transaction_id, category_id| { transaction_id: transaction_id, category_id: category_id } },
        skipped: result.skipped
      }
    end
  end
end
