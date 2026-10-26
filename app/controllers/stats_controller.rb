class StatsController < ApplicationController
  PERIODS = %w[week month year].freeze

  # Defaults to this month. Quick filters pass ?period=week|month|year, the month tabs
  # ?month=YYYY-MM, and the timeline form ?from=&to= (either end may be left open-ended to
  # today / the start of the month). ?currency=DKK shows the amounts in another currency and
  # is remembered in the session.
  def show
    session[:stats_currency] = params[:currency] if params[:currency].present?
    @currency = DisplayCurrency.for(session[:stats_currency])
    session[:stats_scope] = params[:scope] if params[:scope].present?
    @members = Current.user.household_members
    @scope = @members.many? && session[:stats_scope] == "household" ? "household" : "me"
    @today = Time.find_zone("Europe/Helsinki").today
    @months = 11.downto(0).map { |ago| @today.beginning_of_month.months_ago(ago) }
    month = parse_month(params[:month])
    @period = params[:period].presence_in(PERIODS) || ("month" unless month || params[:from].present? || params[:to].present?)
    @range =
      if month
        month.all_month
      elsif @period
        period_range(@period)
      else
        custom_range
      end
    @stats = BankTransactions::Stats.new(@range, users: @scope == "household" ? @members : [ Current.user ])
    # The budget in force for the period, for this scope; the form edits it, or starts a new one.
    @budget_owner = @scope == "household" ? Current.user.household : Current.user
    @budget = Budget.applying_to(@budget_owner, @range)
    @budget_report = BudgetReport.for(@budget, @stats)
    @budget_form = params[:new_budget].present? || @budget.nil? ? Budget.new(starts_on: @range.begin.beginning_of_month) : @budget
    @budget_categories = TransactionCategory.where(user: @stats.users).in_stats.where.missing(:children).distinct.order(:name).pluck(:name)
  end

  private

  def period_range(period)
    case period
    when "week" then @today.all_week
    when "month" then @today.all_month
    when "year" then @today.all_year
    end
  end

  def custom_range
    from = parse_date(params[:from]) || @today.beginning_of_month
    to = parse_date(params[:to]) || @today
    from, to = to, from if from > to
    from..to
  end

  def parse_month(value)
    Date.strptime(value, "%Y-%m") if value.present?
  rescue Date::Error
    nil
  end

  def parse_date(value)
    Date.iso8601(value) if value.present?
  rescue Date::Error
    nil
  end
end
