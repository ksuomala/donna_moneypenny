require "test_helper"

class HouseholdAliasTest < ActiveSupport::TestCase
  test "matches an alias anywhere in the counterparty, whatever the case and spacing" do
    aliases = [ "Jane Marie Doe", "Jane Mobile" ]

    assert HouseholdAlias.match?("JANE MARIE DOE", aliases)
    assert HouseholdAlias.match?("MobilePay  Jane Marie Doe", aliases)
    assert HouseholdAlias.match?("Jane Mobile", aliases)
    assert_not HouseholdAlias.match?("Olivia Doe", aliases)
    assert_not HouseholdAlias.match?(nil, aliases)
    assert_not HouseholdAlias.match?("Jane", [])
  end

  test "names are squished and unique per user" do
    user = users(:one)
    user.household_aliases.create!(name: "  Jane   Doe ")
    assert_equal "Jane Doe", user.household_aliases.first.name
    assert_raises(ActiveRecord::RecordInvalid) { user.household_aliases.create!(name: "jane doe") }
  end
end
