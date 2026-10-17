# An account's balances as the bank reported them on a day: one row per account per day,
# recorded by the daily sync. Booked is signed the bank's way, positive for money in a
# current account and negative for money owed on a credit card.
class BankAccountBalance < ApplicationRecord
  belongs_to :bank_account

  validates :on, presence: true, uniqueness: { scope: :bank_account_id }
  validates :booked, presence: true, numericality: true

  # Enable Banking balance types, most current first. Booked is what has been posted,
  # available what can still be spent (on a card: the limit minus what's used).
  BOOKED_TYPES = %w[ITBD CLBD XPCD].freeze
  AVAILABLE_TYPES = %w[ITAV CLAV FWAV].freeze

  # Maps the "balances" array of GET /accounts/{uid}/balances to our columns, or nil when the
  # bank reported no booked balance.
  def self.attributes_from_api(balances)
    by_type = balances.index_by { |balance| balance["balance_type"] }
    booked = BOOKED_TYPES.filter_map { |type| by_type[type] }.first
    return unless booked

    available = AVAILABLE_TYPES.filter_map { |type| by_type[type] }.first
    {
      booked: BigDecimal(booked.dig("balance_amount", "amount").to_s),
      available: available && BigDecimal(available.dig("balance_amount", "amount").to_s),
      raw: balances
    }
  end
end
