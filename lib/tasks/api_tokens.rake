namespace :api_tokens do
  desc "Create an agent API token (/api) for a user, or for every user without EMAIL. NAME=hermes EMAIL=... " \
       "The token is printed once and only its digest is stored, so copy it straight into the agent's config"
  task create: :environment do
    name = ENV.fetch("NAME")
    users = ENV["EMAIL"].present? ? [ User.find_by!(email_address: ENV["EMAIL"].strip.downcase) ] : User.order(:id).to_a
    users.each do |user|
      token = ApiToken.generate!(user: user, name: name)
      puts "#{user.email_address}\t#{token.name}\t#{token.token}"
    end
  end

  desc "List the API tokens: id, user, name, created, last used (read-only)"
  task list: :environment do
    puts "# id, user, name, created, last used"
    ApiToken.includes(:user).order(:id).each do |token|
      puts [ token.id, token.user.email_address, token.name, token.created_at.to_fs(:db), token.last_used_at&.to_fs(:db) || "never" ].join("\t")
    end
  end

  desc "Revoke an API token. ID=... (from api_tokens:list)"
  task revoke: :environment do
    token = ApiToken.find(ENV.fetch("ID"))
    token.destroy!
    puts "Revoked #{token.name} of #{token.user.email_address}"
  end
end
