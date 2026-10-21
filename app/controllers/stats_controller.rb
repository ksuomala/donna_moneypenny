class StatsController < ApplicationController
  PERIODS = %w[week month year].freeze

  # Defaults to this month. Quick filters pass ?period=week|month|year, the month tabs
  # ?month=YYYY-MM, and the timeline form ?from=&to= (either end may be left open-ended to
  # today / the start of the month).
  def show
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
    @stats = BankTransactions::Stats.new(@range, user: Current.user)
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
