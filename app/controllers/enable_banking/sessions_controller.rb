module EnableBanking
  class SessionsController < ApplicationController
    # Enable Banking redirects end users here (the app's own callback, whitelisted as its
    # "redirect_url" in the Control Panel) once they've completed authorization with their
    # bank, handing us a one-time code we exchange for a session resource. The code is bound
    # to the app that started the login, so the exchange is signed with that app's key.
    def create
      app = Current.user.enable_banking_app
      return redirect_to(root_path, alert: "This bank login was not started with your Enable Banking application.") unless own_callback?(app)
      return redirect_to(root_path, alert: "Bank login was cancelled or failed: #{params[:error_description] || params[:error]}") if params[:error].present?
      return redirect_to(root_path, alert: "Bank login could not be verified. Please try again.") unless valid_state?

      session_data = app.client.create_session(code: params.require(:code))
      connection = Current.user.bank_connections.where(enable_banking_app: app).record_session!(session_data)

      redirect_to root_path, notice: "Connected to #{connection.aspsp_name}: #{connection.bank_accounts.count} account(s)."
    rescue ActionController::ParameterMissing
      redirect_to root_path, alert: "Bank login returned no authorization code."
    rescue EnableBanking::Client::Error => e
      redirect_to root_path, alert: "Could not complete the bank login: #{e.message}"
    end

    private

    # The callback path names the app; it must be the signed-in user's own.
    def own_callback?(app)
      app&.configured? && ActiveSupport::SecurityUtils.secure_compare(app.callback_token, params[:token].to_s)
    end

    # The state we generated when starting the login must come back unchanged, so a
    # login started elsewhere can't be completed into this app.
    def valid_state?
      expected = session.delete(:enable_banking_state)
      expected.present? && params[:state].present? &&
        ActiveSupport::SecurityUtils.secure_compare(expected, params[:state])
    end
  end
end
