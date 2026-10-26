# Budgets are created and edited from the stats page, for the signed-in user or their household.
class BudgetsController < ApplicationController
  before_action :set_budget, only: %i[update destroy]

  def create
    budget = Budget.new(budget_params.merge(owner_attributes))
    if budget.save
      redirect_to stats_path, notice: "Budget saved."
    else
      redirect_to stats_path, alert: "Budget not saved: #{budget.errors.full_messages.join(", ")}"
    end
  end

  def update
    if @budget.update(budget_params)
      redirect_to stats_path, notice: "Budget saved."
    else
      redirect_to stats_path, alert: "Budget not saved: #{@budget.errors.full_messages.join(", ")}"
    end
  end

  def destroy
    @budget.destroy!
    redirect_to stats_path, notice: "Budget removed."
  end

  private

  # Only the signed-in user's own budgets and their household's.
  def set_budget
    own = Budget.where(user: Current.user)
    own = own.or(Budget.where(household: Current.user.household)) if Current.user.household
    @budget = own.find(params[:id])
  end

  def budget_params
    params.expect(budget: [ :starts_on, :ends_on, :monthly_total, { lines_attributes: {} } ])
  end

  # The scope chosen on the stats page: the household only when the user has one.
  def owner_attributes
    if params.dig(:budget, :scope) == "household" && Current.user.household
      { household: Current.user.household }
    else
      { user: Current.user }
    end
  end
end
