namespace :households do
  desc "Put users in one household, whose stats can then be shown combined. NAME=... EMAILS=a@x,b@y " \
       "(a user already in a household is moved; a household left empty is removed)"
  task create: :environment do
    emails = ENV.fetch("EMAILS").split(",").map { |e| e.strip.downcase }.compact_blank
    users = emails.map { |email| User.find_by!(email_address: email) }
    abort "Give at least two users" if users.size < 2

    Household.transaction do
      household = Household.create!(name: ENV.fetch("NAME"))
      users.each { |user| user.update!(household: household) }
      Household.where.missing(:users).destroy_all
      puts "Household #{household.id} #{household.name}: #{users.map(&:email_address).join(", ")}"
    end
  end

  desc "Record the names a user appears under as a counterparty on the other members' accounts, so the household stats " \
       "leave those transactions out. EMAIL=... NAMES=\"Jane Marie Doe|Jane Mobile\" (adds; existing names are kept)"
  task alias: :environment do
    user = User.find_by!(email_address: ENV.fetch("EMAIL").strip.downcase)
    ENV.fetch("NAMES").split("|").map(&:squish).compact_blank.each do |name|
      record = user.household_aliases.find_or_create_by!(name: name)
      puts "#{record.previously_new_record? ? "Added" : "Kept"}\t#{record.name}"
    end
    puts "#{user.email_address} appears as: #{user.household_aliases.order(:name).pluck(:name).join(" | ")}"
  end
end
