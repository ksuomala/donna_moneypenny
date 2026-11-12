module Api
  # The agent API: JSON, authenticated by a bearer token (ApiToken) that acts as one user, so
  # every action sees and changes only Current.user's data, as the web pages do for the
  # signed-in user.
  class BaseController < ActionController::API
    include ActionController::HttpAuthentication::Token::ControllerMethods

    # Before authenticate, so failed attempts count too.
    rate_limit to: 120, within: 1.minute
    before_action :authenticate

    rescue_from(ActiveRecord::RecordNotFound) { |e| render_error e.message, :not_found }
    rescue_from(ActionController::ParameterMissing) { |e| render_error e.message, :bad_request }
    rescue_from(ActiveRecord::RecordInvalid) { |e| render_error e.record.errors.full_messages.to_sentence, :unprocessable_entity }
    # The services raise ArgumentError for input they can't take (an unknown category, a bad date).
    rescue_from(ArgumentError) { |e| render_error e.message, :unprocessable_entity }

    private

    def authenticate
      token = authenticate_with_http_token { |value, _options| ApiToken.authenticate(value) }
      return render_error("Missing or unknown API token", :unauthorized) unless token

      Current.user = token.user
    end

    # The user, or with scope=household their household, like the stats page's scope switch.
    def owner
      return Current.user unless params[:scope] == "household"

      Current.user.household || raise(ActiveRecord::RecordNotFound, "#{Current.user.email_address} has no household")
    end

    def scope_name = owner.is_a?(Household) ? "household" : "me"

    def dry_run? = ActiveModel::Type::Boolean.new.cast(params[:dry_run]) || false

    def render_error(message, status)
      render json: { error: message }, status: status
    end

    def budget_row_json(row)
      { name: row.name, budget: row.budget, spent: row.spent, left: row.left, percent: row.percent, over: row.over? }
    end

    def transaction_json(transaction)
      { id: transaction.id, account_id: transaction.bank_account_id, date: transaction.occurred_on, amount: transaction.amount,
        currency: transaction.currency, counterparty: transaction.counterparty_name, description: transaction.description,
        reference: transaction.reference_number, category_id: transaction.transaction_category_id }
    end
  end
end
