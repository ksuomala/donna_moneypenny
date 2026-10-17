module EnableBanking
  # Starts a bank login: asks Enable Banking for an authorization URL and sends the user
  # to the bank. The bank later redirects back to SessionsController#create.
  class AuthorizationsController < ApplicationController
    ASPSP_NAME = "Nordea"
    ASPSP_COUNTRY = "FI"
    FALLBACK_CONSENT_VALIDITY = 90.days

    def create
      client = EnableBanking::Client.build
      state = SecureRandom.urlsafe_base64(32)
      session[:enable_banking_state] = state

      authorization = client.start_authorization(
        aspsp_name: ASPSP_NAME,
        country: ASPSP_COUNTRY,
        redirect_url: redirect_url,
        state: state,
        valid_until: consent_valid_until(client)
      )

      redirect_to authorization.fetch("url"), allow_other_host: true
    rescue EnableBanking::Client::Error => e
      redirect_to root_path, alert: "Could not start the bank login: #{e.message}"
    end

    private

    def redirect_url
      Rails.configuration.x.enable_banking.redirect_url || enable_banking_sessions_url
    end

    # Ask for the longest consent the bank allows (Nordea: 180 days), minus a safety margin.
    def consent_valid_until(client)
      aspsp = client.aspsps(country: ASPSP_COUNTRY).find { |a| a["name"] == ASPSP_NAME }
      validity = aspsp&.dig("maximum_consent_validity")&.seconds || FALLBACK_CONSENT_VALIDITY

      validity.from_now - 1.hour
    end
  end
end
