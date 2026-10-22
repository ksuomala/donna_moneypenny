namespace :categories do
  # Every task here is the acting user's (EMAIL=..., default the owner; lib/tasks/acting_user.rake).

  desc "Print every category: id, name, kind, parent, description (read-only). EMAIL=... for another user"
  task list: :environment do
    TransactionCategory.where(user: acting_user).includes(:parent).order(:id).each do |category|
      kind = category.exclude_from_stats? ? "excluded" : category.kind
      puts [ category.id, category.name, kind, category.parent&.name, category.description ].join("\t")
    end
  end

  desc "Create or update one category. NAME=... KIND=expense|income|investment|excluded PARENT=... DESCRIPTION=... (KIND and PARENT can be left out when updating). EMAIL=... for another user"
  task upsert: :environment do
    category = TransactionCategory.define!(name: ENV.fetch("NAME"), kind: ENV["KIND"].presence, parent: ENV["PARENT"].presence, description: ENV["DESCRIPTION"], user: acting_user)
    puts [ category.previously_new_record? ? "Created" : "Updated", category.id, category.name ].join("\t")
  end

  desc "Create or update categories from YAML ({categories: [{name, kind, description, children: [{name, description}]}]}). YAML=path, or YAML_B64=base64 of the file, which survives any shell quoting (e.g. through Kamal). EMAIL=... for another user"
  task import: :environment do
    yaml = ENV["YAML_B64"].present? ? ENV["YAML_B64"].unpack1("m0") : File.read(ENV.fetch("YAML"))
    TransactionCategory.import!(YAML.safe_load(yaml).fetch("categories"), user: acting_user).each do |category|
      puts [ category.previously_new_record? ? "Created" : "Updated", category.id, category.name ].join("\t")
    end
  end
end
