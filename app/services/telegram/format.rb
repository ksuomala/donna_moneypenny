module Telegram
  # Text helpers for the messages: amounts in euros as on the stats page, names escaped for
  # Telegram's HTML.
  module Format
    TIME_ZONE = "Europe/Helsinki".freeze

    module_function

    def today = Time.find_zone(TIME_ZONE).today

    def money(amount)
      ActiveSupport::NumberHelper.number_to_currency(amount, unit: "€", format: "%n %u", separator: ",", delimiter: " ")
    end

    def signed_money(amount)
      amount.zero? ? money(0) : "#{amount.positive? ? "+" : "−"}#{money(amount.abs)}"
    end

    def escape(text) = ERB::Util.html_escape(text.to_s)

    def bold(text) = "<b>#{escape(text)}</b>"

    # "Cafes: 80,00 € of 50,00 € · 30,00 € over", as the stats page puts it.
    def budget_row(row)
      left = row.over? ? "#{money(-row.left)} over" : "#{money(row.left)} left"
      "#{escape(row.name)}: #{money(row.spent)} of #{money(row.budget)} · #{left}"
    end
  end
end
