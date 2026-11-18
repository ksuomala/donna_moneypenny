module StatsHelper
  # The pie palette has nine colors; past that the smallest categories fold into "Other".
  PIE_COLORS = 9
  NET_WORTH_DATE_LABELS = 6

  PieSlice = Data.define(:name, :amount, :color)

  # An amount (stored in euros) in the page's display currency (@currency, euros by default).
  def money(amount)
    currency = @currency || DisplayCurrency.new(ExchangeRate::BASE)
    number_to_currency(currency.convert(amount), unit: currency.unit, format: "%n %u", separator: ",", delimiter: " ")
  end

  # With an explicit sign, for changes: "+2 000,00 €", "−819,26 €".
  def signed_money(amount)
    amount.zero? ? money(0) : "#{amount.positive? ? "+" : "−"}#{money(amount.abs)}"
  end

  # Short, for chart axes: "120 k €", "1,2 M €".
  def compact_money(amount)
    currency = @currency || DisplayCurrency.new(ExchangeRate::BASE)
    value = currency.convert(amount)
    if value.abs >= 1_000_000
      "#{number_with_precision(value / 1_000_000, precision: 1, separator: ",", strip_insignificant_zeros: true)} M #{currency.unit}"
    elsif value.abs >= 10_000
      "#{number_with_precision(value / 1_000, precision: 0)} k #{currency.unit}"
    else
      "#{number_with_precision(value, precision: 0, delimiter: " ")} #{currency.unit}"
    end
  end

  # "▲ 12 % vs Oct": an amount against the same total in the previous period.
  def period_change(amount, previous, against:, higher_is_better:)
    return if previous.zero?

    percent = ((amount - previous) * 100 / previous).round
    versus = "vs #{previous_period_name(against)}"
    return tag.span("No change #{versus}", class: "muted trend") if percent.zero?

    better = percent.positive? == higher_is_better
    tag.span("#{percent.positive? ? "▲" : "▼"} #{percent.abs} % #{versus}", class: [ "trend", better ? "trend-better" : "trend-worse" ])
  end

  def previous_period_name(range)
    if range == range.begin.all_month
      l(range.begin, format: "%b")
    elsif range == range.begin.all_year
      range.begin.year.to_s
    else
      "previous period"
    end
  end

  # Month links use ?month= so the month tab lights up; anything else is a from–to range.
  def stats_range_path(range)
    if range == range.begin.all_month
      stats_path(month: range.begin.strftime("%Y-%m"))
    else
      stats_path(from: range.begin.iso8601, to: range.end.iso8601)
    end
  end

  def transaction_date(date, range)
    l(date, format: range.begin.year == range.end.year ? "%-d %b" : "%-d %b %Y")
  end

  # An explanatory note behind an ⓘ toggle, to sit next to a section heading.
  def info_note(&)
    tag.details(class: "info") do
      tag.summary("ⓘ", title: "About these numbers", "aria-label": "About these numbers") +
        tag.div(capture(&), class: "info-body muted")
    end
  end

  def share(amount, total)
    total.zero? ? "0 %" : "#{(amount * 100 / total).round} %"
  end

  def stats_period_label(range)
    if range == range.begin.all_month
      l(range.begin, format: "%B %Y")
    elsif range == range.begin.all_year
      range.begin.year.to_s
    else
      "#{l range.begin, format: :long} – #{l range.end, format: :long}"
    end
  end

  # Largest first, colored by rank within this pie; "Other" and "Uncategorized" come last in
  # their own neutral colors.
  def pie_slices(slices)
    uncategorized, categorized = slices.partition(&:uncategorized?)
    shown, rest = categorized.size > PIE_COLORS ? [ categorized.first(PIE_COLORS - 1), categorized.drop(PIE_COLORS - 1) ] : [ categorized, [] ]

    parts = shown.each_with_index.map { |slice, index| PieSlice.new(name: slice.name, amount: slice.amount, color: index + 1) }
    parts << PieSlice.new(name: "Other", amount: rest.sum(&:amount), color: "other") if rest.any?
    parts + uncategorized.map { |slice| PieSlice.new(name: slice.name, amount: slice.amount, color: "uncategorized") }
  end

  # An SVG pie (a donut, so the total fits in the middle) with one path per slice.
  def pie_chart(slices, total:)
    radius = 100
    inner = 58
    angle = -Math::PI / 2

    paths = slices.map do |slice|
      sweep = 2 * Math::PI * (slice.amount / total).to_f
      path = donut_segment(angle, [ sweep, 2 * Math::PI - 0.0001 ].min, radius, inner)
      angle += sweep
      tag.path(d: path, class: "pie-slice series-#{slice.color}") do
        tag.title("#{slice.name}: #{money(slice.amount)} (#{share(slice.amount, total)})")
      end
    end

    tag.svg(viewBox: "-102 -102 204 204", class: "pie", role: "img", "aria-label": "Pie chart") do
      safe_join(paths) +
        tag.text(money(total), x: 0, y: 5, "text-anchor": "middle", class: "pie-total")
    end
  end

  def net_worth_chart(points)
    values = points.map(&:amount)
    minimum, maximum = values.minmax
    padding = maximum == minimum ? [ maximum.abs * 0.05, 1 ].max : (maximum - minimum) * 0.08
    minimum -= padding
    maximum += padding

    width = 720
    height = 260
    left = 76
    right = 24
    top = 18
    bottom = 38
    plot_width = width - left - right
    plot_height = height - top - bottom
    date_span = [ (points.last.date - points.first.date).to_f, 1 ].max
    coordinates = points.map do |point|
      x = left + ((point.date - points.first.date).to_f / date_span * plot_width)
      y = top + ((maximum - point.amount).to_f / (maximum - minimum) * plot_height)
      [ point, x, y ]
    end
    grid = [ minimum, (minimum + maximum) / 2, maximum ].map do |value|
      y = top + ((maximum - value).to_f / (maximum - minimum) * plot_height)
      safe_join([
        tag.line(x1: left, y1: y, x2: width - right, y2: y, class: "net-worth-grid"),
        tag.text(compact_money(value), x: left - 8, y: y + 5, class: "net-worth-label", "text-anchor": "end")
      ])
    end
    line = tag.polyline(points: coordinates.map { |_point, x, y| "#{x.round(1)},#{y.round(1)}" }.join(" "), class: "net-worth-line")
    markers = coordinates.map do |point, x, y|
      tag.circle(cx: x, cy: y, r: 4, class: "net-worth-point") do
        tag.title("#{l(point.date, format: :long)}: #{money(point.amount)}")
      end
    end
    every = (coordinates.size / NET_WORTH_DATE_LABELS.to_f).ceil
    labelled = coordinates.reverse.each_slice(every).map(&:first)
    dates = labelled.map do |point, x, _y|
      tag.text(l(point.date, format: "%b %y"), x: x, y: height - 8, class: "net-worth-label", "text-anchor": "middle")
    end

    tag.svg(viewBox: "0 0 #{width} #{height}", class: "net-worth-chart", role: "img", "aria-label": "Net worth over time") do
      safe_join(grid + [ line ] + markers + dates)
    end
  end

  private

  def donut_segment(start, sweep, outer, inner)
    finish = start + sweep
    large = sweep > Math::PI ? 1 : 0
    point = ->(r, a) { format("%.3f %.3f", r * Math.cos(a), r * Math.sin(a)) }

    "M #{point.(outer, start)} A #{outer} #{outer} 0 #{large} 1 #{point.(outer, finish)} " \
      "L #{point.(inner, finish)} A #{inner} #{inner} 0 #{large} 0 #{point.(inner, start)} Z"
  end
end
