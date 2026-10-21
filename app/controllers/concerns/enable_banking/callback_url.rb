module EnableBanking
  # The URL the bank login of an app returns to. Each app has its own, and it must exactly match
  # the redirect URL whitelisted for that app in the Enable Banking Control Panel.
  module CallbackUrl
    extend ActiveSupport::Concern

    included do
      helper_method :enable_banking_callback_url_for
    end

    private

    def enable_banking_callback_url_for(app)
      host = Rails.configuration.x.enable_banking.callback_host
      enable_banking_callback_url(app.callback_token, **(host ? { host: host, protocol: "https" } : {}))
    end
  end
end
