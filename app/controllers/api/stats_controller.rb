module Api
  # Income and spending per category for a date range, in the stats page's scope and euros, with
  # the budget in force prorated to the range. from and to are dates, both included.
  class StatsController < BaseController
    def show
      range = date_range
      stats = BankTransactions::Stats.new(range, users: Telegram::Chats.members(owner))
      budget = BudgetReport.for(Budget.applying_to(owner, range), stats)

      render json: {
        scope: scope_name,
        from: range.begin,
        to: range.end,
        income: stats.income_total,
        expenses: stats.expense_total,
        net: stats.net,
        incomes: stats.incomes.map { |slice| slice_json(slice) },
        spending: stats.expenses.map { |slice| slice_json(slice) },
        budget: budget && { from: budget.range.begin, to: budget.range.end, total: budget.total && budget_row_json(budget.total),
                            lines: budget.rows.map { |row| budget_row_json(row) } }
      }
    end

    private

    def slice_json(slice) = { category: slice.name, kind: slice.kind, amount: slice.amount }
  end
end
