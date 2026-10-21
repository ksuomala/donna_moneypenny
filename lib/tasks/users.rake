require "io/console"

namespace :users do
  desc "Create a user who can sign in. EMAIL=... (asks for the password, or PASSWORD=... without a terminal). " \
       "The first user also gets every record that has no owner yet, i.e. all the data from before there were users"
  task create: :environment do
    email = ENV.fetch("EMAIL")
    password = read_user_password

    User.transaction do
      user = User.create!(email_address: email, password: password)
      puts "Created user #{user.id} #{user.email_address}"
      next unless user == User.owner

      user.claim_unowned_records!.each { |model, count| puts "  #{count}\t#{model}" }
    end
  end

  desc "Set a user's password (there is no reset by email). EMAIL=... (asks for the password, or PASSWORD=...)"
  task password: :environment do
    user = User.find_by!(email_address: ENV.fetch("EMAIL").strip.downcase)
    user.update!(password: read_user_password)
    user.sessions.destroy_all
    puts "Changed the password of #{user.email_address} and signed out its sessions"
  end

  def read_user_password
    return ENV["PASSWORD"] if ENV["PASSWORD"].present?
    abort "No terminal to ask for the password: set PASSWORD=..." unless $stdin.tty?

    password = $stdin.getpass("Password: ")
    abort "The passwords don't match" unless password == $stdin.getpass("Again: ")
    password
  end
end
