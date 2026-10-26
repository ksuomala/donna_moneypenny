# An account's balances as the bank reported them on a day: one row per account per day,
# recorded by the daily sync. Booked is signed the bank's way, positive for money in a
# current account and negative for money owed on a credit card. booked_type and
# available_type say which of the bank's balance types each amount came from. Amounts are in
# euros; an account in another currency keeps the bank's figures in source_*.
class BankAccountBalance < ApplicationRecord
  belongs_to :bank_account

  validates :on, presence: true, uniqueness: { scope: :bank_account_id }
  validates :booked, presence: true, numericality: true

  # Enable Banking balance types, most current first. Booked is what has been posted,
  # available what can still be spent (on a card: the limit minus what's used).
  BOOKED_TYPES = %w[ITBD CLBD XPCD].freeze
  AVAILABLE_TYPES = %w[ITAV CLAV FWAV].freeze

  # Maps the "balances" array of GET /accounts/{uid}/balances to our columns, or nil when the
  # bank reported neither. Revolut reports only an available balance; with nothing pending it
  # is the booked balance too, so it stands in for it.
  def self.attributes_from_api(balances)
    by_type = balances.index_by { |balance| balance["balance_type"] }
    available = AVAILABLE_TYPES.filter_map { |type| by_type[type] }.first
    booked = BOOKED_TYPES.filter_map { |type| by_type[type] }.first || available
    return unless booked

    {
      booked: BigDecimal(booked.dig("balance_amount", "amount").to_s),
      booked_type: booked["balance_type"],
      available: available && BigDecimal(available.dig("balance_amount", "amount").to_s),
      available_type: available && available["balance_type"],
      raw: balances
    }
  end
end
