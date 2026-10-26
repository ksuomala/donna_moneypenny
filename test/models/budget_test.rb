require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  test "belongs to a user or a household, not both or neither" do
    household = Household.create!(name: "Us")

    assert Budget.new(user: users(:one), starts_on: Date.new(2026, 10, 1)).valid?
    assert Budget.new(household: household, starts_on: Date.new(2026, 10, 1)).valid?
    assert_not Budget.new(starts_on: Date.new(2026, 10, 1)).valid?
    assert_not Budget.new(user: users(:one), household: household, starts_on: Date.new(2026, 10, 1)).valid?
    assert_not Budget.new(user: users(:one), starts_on: Date.new(2026, 10, 1), ends_on: Date.new(2026, 9, 1)).valid?
  end

  test "months in a period count each calendar month by its share of days" do
    assert_equal 1, Budget.months_in(Date.new(2026, 10, 1).all_month)
    assert_equal 12, Budget.months_in(Date.new(2026, 1, 1).all_year)
    assert_in_delta 7.0 / 31, Budget.months_in(Date.new(2026, 10, 5)..Date.new(2026, 10, 11)), 0.001
    assert_in_delta 1.5, Budget.months_in(Date.new(2026, 9, 16)..Date.new(2026, 10, 31)), 0.001
  end

  test "the budget applying to a period is the latest-starting one overlapping it, and covers only its own window" do
    user = users(:one)
    old = user.budgets.create!(starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 6, 30), monthly_total: 1000)
    current = user.budgets.create!(starts_on: Date.new(2026, 7, 1), monthly_total: 1200)

    assert_equal old, Budget.applying_to(user, Date.new(2026, 3, 1).all_month)
    assert_equal current, Budget.applying_to(user, Date.new(2026, 10, 1).all_month)
    assert_equal current, Budget.applying_to(user, Date.new(2026, 6, 20)..Date.new(2026, 7, 10))
    assert_nil Budget.applying_to(user, Date.new(2025, 12, 1).all_month)
    assert_nil Budget.applying_to(users(:two), Date.new(2026, 10, 1).all_month)

    assert_equal Date.new(2026, 7, 1)..Date.new(2026, 7, 10), current.covered(Date.new(2026, 6, 20)..Date.new(2026, 7, 10))
    assert_equal Date.new(2026, 6, 20)..Date.new(2026, 6, 30), old.covered(Date.new(2026, 6, 20)..Date.new(2026, 7, 10))
    assert_nil old.covered(Date.new(2026, 10, 1).all_month)
  end

  test "lines are replaced from name => amount pairs, blank and zero amounts dropped" do
    budget = users(:one).budgets.create!(starts_on: Date.new(2026, 10, 1), lines_attributes: { "Groceries" => "400", "Cafes" => "", "Shopping" => "0" })
    assert_equal [ [ "Groceries", 400 ] ], budget.lines.map { [ it.category_name, it.monthly_amount ] }

    budget.update!(lines_attributes: { "Groceries" => "350,50", "Restaurants" => "200" })
    assert_equal [ [ "Groceries", BigDecimal("350.50") ], [ "Restaurants", 200 ] ], budget.lines.order(:category_name).map { [ it.category_name, it.monthly_amount ] }
  end
end
