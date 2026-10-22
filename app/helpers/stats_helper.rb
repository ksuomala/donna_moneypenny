module StatsHelper
  # The pie palette has nine colors; past that the smallest categories fold into "Other".
  PIE_COLORS = 9

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

  private

  def donut_segment(start, sweep, outer, inner)
    finish = start + sweep
    large = sweep > Math::PI ? 1 : 0
    point = ->(r, a) { format("%.3f %.3f", r * Math.cos(a), r * Math.sin(a)) }

    "M #{point.(outer, start)} A #{outer} #{outer} 0 #{large} 1 #{point.(outer, finish)} " \
      "L #{point.(inner, finish)} A #{inner} #{inner} 0 #{large} 0 #{point.(inner, start)} Z"
  end
end
