# The names a household member appears under as a counterparty on the other members'
# accounts ("JANE MARIE DOE", "Jane Mobile", "Alex Example"). The household stats leave
# out every transaction with another member as the counterparty, whatever its category.
class CreateHouseholdAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :household_aliases do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :household_aliases, %i[user_id name], unique: true
  end
end
