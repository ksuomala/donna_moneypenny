# A budget against the spending of a period: the monthly amounts prorated to the months the
# period covers (Budget.months_in), the total and each line with what was spent and what is
# left. spent comes from the period's stats (BankTransactions::Stats), so it is in the same
# scope (user or household) and the same euros as the rest of the page.
class BudgetReport
  Row = Data.define(:name, :budget, :spent) do
    def left = budget - spent
    def over? = spent > budget
    # Share of the budget used, in whole percent; used is capped for drawing.
    def percent = budget.zero? ? 0 : (spent * 100 / budget).round
    def used = [ percent, 100 ].min
  end

  attr_reader :budget, :range, :months

  # nil when the budget covers none of the period.
  def self.for(budget, stats)
    return unless budget && (covered = budget.covered(stats.range))

    new(budget, stats, covered)
  end

  def initialize(budget, stats, covered)
    @budget = budget
    @partial = covered != stats.range
    # When the budget covers only part of the period, the spending measured is that part's.
    @stats = @partial ? BankTransactions::Stats.new(covered, users: stats.users) : stats
    @range = covered
    @months = Budget.months_in(covered)
  end

  def partial? = @partial

  def total
    return unless budget.monthly_total

    Row.new(name: "Total", budget: prorate(budget.monthly_total), spent: @stats.expense_total)
  end

  def rows
    spent = @stats.expenses.to_h { |slice| [ slice.name, slice.amount ] }
    budget.lines.sort_by(&:category_name).map do |line|
      Row.new(name: line.category_name, budget: prorate(line.monthly_amount), spent: spent.fetch(line.category_name, BigDecimal(0)))
    end
  end

  private

  def prorate(monthly) = (monthly * months).round(2)
end
