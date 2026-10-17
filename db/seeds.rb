# Default transaction categories. Create-only: running db:seed again never touches a category
# that already exists, so the owner's own descriptions and sub-categories are safe in every
# environment. Add or change categories with bin/rails categories:upsert or categories:import
# (see lib/tasks/categories.rake); bin/rails categories:list prints what the database has.
#
# The descriptions are the instructions an LLM follows when categorizing (printed by
# transactions:categorization_context), so keep them precise about borderline cases.
# Categories with sub-categories are never assigned directly. "excluded" categories (own
# transfers, loan payments, large purchases) are left out of reports and statistics.
[
  [ "Groceries", "expense", "Grocery stores and supermarkets, at home and abroad." ],
  [ "Restaurants", "expense", "Eating and drinking out, including food delivery." ],
  [ "Cafes", "expense", "Coffee shops, cakes and pastries." ],
  [ "Flights and airport", "expense", "Flight tickets and airport fees." ],
  [ "Hotels and accommodation", "expense", "Hotels, hostels, holiday rentals, camping fees." ],
  [ "Subscriptions", "expense", "Recurring services: hosting, phone bill, streaming." ],
  [ "Hardware store", "expense", "Hardware and DIY stores, tools and gear." ],
  [ "Household", "expense", "Electricity, housing company charges, renovation, home insurance." ],
  [ "Furniture", "expense", "Furniture and home furnishing stores." ],
  [ "Shopping", "expense", "Clothing, shoes and other shopping." ],
  [ "Car", "expense", "Costs of owning a car: fuel, vehicle tax, insurance, parking, parts and repairs. Buying a car is a Value purchase." ],
  [ "Transport", "expense", "Getting around without your own car: taxis, ride-hailing, trains, buses, ferries." ],
  [ "Cash", "expense", "ATM withdrawals, including any withdrawal fee." ],
  [ "Fees & taxes", "expense", "Bank fees, parking tickets, taxes." ],
  [ "Health", "expense", "Pharmacy, doctor, dentist, physiotherapist, personal trainer." ],
  [ "Hobbies", "expense", "Sports and gym memberships, music, museums, other hobbies." ],
  [ "Education and books", "expense", "Books, courses and other learning." ],
  [ "Child", "expense", "Children: baby and maternity gear, childcare, school." ],
  [ "Loans", "excluded", "All money moving through a loan: payments (principal and interest), loans paid out to you, and interest and fees charged on credit cards. The credit card invoice payment itself is Own." ],
  [ "Own", "excluded", "Transfers between your own accounts and to your own credit cards, on both sides. Interest and fees are never part of it; they go to Loans." ],
  [ "Salary", "income", "Salary payments from an employer." ],
  [ "Investment", "investment", "Rental properties and other investments. Add one sub-category per investment and always use the sub-category." ],
  [ "Value purchase", "excluded", "Large purchases of lasting value, like a home or a car. Add one sub-category per purchase and always use the sub-category." ]
].each do |name, kind, description|
  TransactionCategory.find_or_create_by!(name: name) do |category|
    category.exclude_from_stats = (kind == "excluded")
    category.kind = kind unless kind == "excluded"
    category.description = description
  end
end
