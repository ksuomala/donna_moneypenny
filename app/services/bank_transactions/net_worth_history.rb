module BankTransactions
  class NetWorthHistory
    Point = Data.define(:date, :amount, :unknown_balance_count)
    Change = Data.define(:label, :amount)
    Result = Data.define(:current, :points, :changes)

    PERIODS = [ [ 1, "1 month" ], [ 3, "Quarter" ], [ 6, "6 months" ], [ 12, "12 months" ] ].freeze

    def initialize(users:)
      @net_worth = NetWorth.new(users:)
    end

    def call(at: Time.current)
      at = at.in_time_zone(NetWorth::TIME_ZONE)
      samples = PERIODS.map do |months_ago, label|
        [ months_ago, label, @net_worth.call(at: at.advance(months: -months_ago)) ]
      end
      current = @net_worth.call(at:)
      points = samples.map do |months_ago, _label, result|
        Point.new(date: at.advance(months: -months_ago).to_date, amount: result.amount, unknown_balance_count: result.unknown_balance_count)
      end
      points << Point.new(date: at.to_date, amount: current.amount, unknown_balance_count: current.unknown_balance_count)
      changes = samples.map do |_months_ago, label, previous|
        Change.new(label:, amount: current.amount - previous.amount)
      end

      Result.new(current:, points: points.sort_by(&:date), changes:)
    end
  end
end
