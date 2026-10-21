namespace :enable_banking do
  desc "Give a user (EMAIL=..., default the owner) the Enable Banking application from the Rails credentials " \
       "(enable_banking.application_id / private_key), from before each user had their own, and link that user's " \
       "connections that have no application to it. Fills in only: an application already entered is kept"
  task claim_credentials: :environment do
    user = ENV["EMAIL"].present? ? User.find_by!(email_address: ENV["EMAIL"].strip.downcase) : User.owner
    abort "No users yet: bin/rails users:create first" unless user

    credentials = Rails.application.credentials.enable_banking
    abort "No enable_banking credentials to claim" if credentials.blank?

    app = user.enable_banking_app || user.build_enable_banking_app
    if app.configured?
      puts "#{user.email_address} already has an application (#{app.application_id}); kept"
    else
      app.update!(application_id: credentials[:application_id], private_key: credentials[:private_key])
      puts "#{user.email_address}: application #{app.application_id} from the credentials"
    end

    linked = user.bank_connections.where(enable_banking_app_id: nil).update_all(enable_banking_app_id: app.id)
    puts "  #{linked} connection(s) linked to it"
    puts "Add this redirect URL to the application in the Enable Banking Control Panel before the next bank login:"
    host = Rails.configuration.x.enable_banking.callback_host
    puts "  #{host ? "https://#{host}" : "http://localhost:3000"}" \
         "#{Rails.application.routes.url_helpers.enable_banking_callback_path(app.callback_token)}"
  end
end
