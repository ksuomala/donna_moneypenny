require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(@user = users(:one))
    connection = @user.bank_connections.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", currency: "EUR")
    @groceries = @user.transaction_categories.create!(name: "Groceries", kind: :expense)
    @today = Time.find_zone("Europe/Helsinki").today
    @account.bank_transactions.create!(entry_reference: "a", occurred_on: @today, amount: -120, currency: "EUR", transaction_category: @groceries)
  end

  test "the stats page offers a budget form and shows the saved budget against the month" do
    get stats_path
    assert_select ".budget p.muted", "No budget for this period yet."
    assert_select "form.budget-form input[name='budget[lines_attributes][Groceries]']"

    assert_difference "Budget.count", 1 do
      post budgets_path, params: { budget: { scope: "me", starts_on: @today.beginning_of_month, monthly_total: "1000", lines_attributes: { "Groceries" => "400" } } }
    end
    assert_redirected_to stats_path
    budget = Budget.last
    assert_equal @user, budget.user
    assert_nil budget.household

    follow_redirect!
    assert_select ".budget-row-total .bar-value", /120,00 €.*of 1 000,00 €.*880,00 € left/m
    assert_select ".budget-row:not(.budget-row-total) .bar-value", /120,00 €.*of 400,00 €.*280,00 € left/m
    assert_select "summary", "Edit this budget"

    patch budget_path(budget), params: { budget: { starts_on: @today.beginning_of_month, monthly_total: "", lines_attributes: { "Groceries" => "100" } } }
    follow_redirect!
    assert_select ".budget-row-total", 0
    assert_select ".budget-row-over .bar-value", /20,00 € over/

    delete budget_path(budget)
    assert_equal 0, Budget.count
  end

  test "a household budget is shown in the household scope only" do
    household = Household.create!(name: "Us")
    [ @user, users(:two) ].each { |u| u.update!(household: household) }

    post budgets_path, params: { budget: { scope: "household", starts_on: @today.beginning_of_month, monthly_total: "2000" } }
    assert_equal household, Budget.last.household

    get stats_path(scope: "household")
    assert_select ".budget-row-total .bar-value", /of 2 000,00 €/
    get stats_path(scope: "me")
    assert_select ".budget p.muted", "No budget for this period yet."
  end

  test "another user's budget can't be edited" do
    theirs = users(:two).budgets.create!(starts_on: @today, monthly_total: 1)

    patch budget_path(theirs), params: { budget: { monthly_total: "5" } }
    assert_response :not_found
    assert_equal 1, theirs.reload.monthly_total
  end

  test "an invalid budget is reported, not saved" do
    post budgets_path, params: { budget: { scope: "me", starts_on: @today, ends_on: @today - 1 } }

    assert_redirected_to stats_path
    assert_match "must be after the start", flash[:alert]
    assert_equal 0, Budget.count
  end
end
