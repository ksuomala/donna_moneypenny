module EnableBanking
  class SessionsController < ApplicationController
    # Enable Banking redirects end users here (the "redirect_url" whitelisted
    # in the Control Panel) once they've completed authorization with their
    # bank, handing us a one-time code we exchange for a session resource.
    def create
      return redirect_to(root_path, alert: "Bank login was cancelled or failed: #{params[:error_description] || params[:error]}") if params[:error].present?
      return redirect_to(root_path, alert: "Bank login could not be verified. Please try again.") unless valid_state?

      session_data = EnableBanking::Client.build.create_session(code: params.require(:code))
      connection = BankConnection.record_session!(session_data)

      redirect_to root_path, notice: "Connected to #{connection.aspsp_name}: #{connection.bank_accounts.count} account(s)."
    rescue ActionController::ParameterMissing
      redirect_to root_path, alert: "Bank login returned no authorization code."
    rescue EnableBanking::Client::Error => e
      redirect_to root_path, alert: "Could not complete the bank login: #{e.message}"
    end

    private

    # The state we generated when starting the login must come back unchanged, so a
    # login started elsewhere can't be completed into this app.
    def valid_state?
      expected = session.delete(:enable_banking_state)
      expected.present? && params[:state].present? &&
        ActiveSupport::SecurityUtils.secure_compare(expected, params[:state])
    end
  end
end
