# A household groups users whose stats can be shown together (the stats page's Household
# scope). Nothing else is shared: each user keeps their own connections, categories and loans.
class CreateHouseholds < ActiveRecord::Migration[8.1]
  def change
    create_table :households do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_reference :users, :household, foreign_key: true
  end
end
