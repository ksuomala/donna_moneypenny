module EnableBanking
  # The signed-in user's own Enable Banking application: its callback URL to register in the
  # Control Panel, and the application ID and private key the Control Panel gives back.
  class AppsController < ApplicationController
    include CallbackUrl

    # The app exists from the first visit, so its callback URL can be registered before the
    # application ID is known.
    before_action { @app = Current.user.enable_banking_app || Current.user.create_enable_banking_app! }

    def show
    end

    # Saves the credentials once Enable Banking accepts them. The key comes from the uploaded
    # .pem file or the text field; neither keeps the stored one.
    def update
      @app.application_id = app_params[:application_id]
      private_key = app_params[:private_key_file]&.read.presence || app_params[:private_key]
      @app.private_key = private_key if private_key.present?

      if @app.valid?(:credentials) && credentials_accepted? && @app.save(context: :credentials)
        redirect_to root_path, notice: "Enable Banking application saved."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def app_params
      params.expect(enable_banking_app: %i[application_id private_key private_key_file])
    end

    # A signed request proves the ID and key belong together and the app is active.
    def credentials_accepted?
      @app.client.aspsps(country: AuthorizationsController::ASPSP_COUNTRY)
      true
    rescue EnableBanking::Client::Error => e
      @app.errors.add(:base, "Enable Banking did not accept these credentials: #{e.message}")
      false
    end
  end
end
