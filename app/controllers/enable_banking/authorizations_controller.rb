module EnableBanking
  # Starts a bank login with the signed-in user's own Enable Banking application: asks it for an
  # authorization URL and sends the user to the bank. The bank later redirects back to the app's
  # callback, SessionsController#create.
  class AuthorizationsController < ApplicationController
    include CallbackUrl

    FALLBACK_CONSENT_VALIDITY = 90.days

    def create
      app = Current.user.enable_banking_app
      return redirect_to(enable_banking_app_path, alert: "Set up your Enable Banking application first.") unless app&.configured?

      bank = Bank.find(params[:bank])
      return redirect_to(root_path, alert: "Unknown bank.") unless bank

      client = app.client
      state = SecureRandom.urlsafe_base64(32)
      session[:enable_banking_state] = state

      authorization = client.start_authorization(
        aspsp_name: bank.name,
        country: bank.country,
        redirect_url: enable_banking_callback_url_for(app),
        state: state,
        valid_until: consent_valid_until(client, bank)
      )

      redirect_to authorization.fetch("url"), allow_other_host: true
    rescue EnableBanking::Client::Error => e
      redirect_to root_path, alert: "Could not start the bank login: #{e.message}"
    end

    private

    # Ask for the longest consent the bank allows (Nordea and Revolut: 180 days), minus a safety margin.
    def consent_valid_until(client, bank)
      aspsp = client.aspsps(country: bank.country).find { |a| a["name"] == bank.name }
      validity = aspsp&.dig("maximum_consent_validity")&.seconds || FALLBACK_CONSENT_VALIDITY

      validity.from_now - 1.hour
    end
  end
end
