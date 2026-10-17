# An account the user connected through Enable Banking. Credit cards are CreditCard
# (single-table inheritance, chosen from the bank's account type when the account is attached).
class BankAccount < ApplicationRecord
  belongs_to :bank_connection
  has_many :bank_transactions, dependent: :destroy
  has_many :balances, class_name: "BankAccountBalance", dependent: :destroy

  validates :uid, presence: true, uniqueness: true

  # Current and savings accounts, i.e. not credit cards.
  scope :deposit, -> { where(type: [ nil, "BankAccount" ]) }

  # The subclass for an account resource from the API, or nil for a plain account.
  def self.type_from_api(account)
    "CreditCard" if account["cash_account_type"] == "CARD"
  end

  def credit_card? = false

  # Account type plus the last digits of the IBAN, e.g. "Käyttötili …3458".
  def display_name
    [ name.presence, iban.present? ? "…#{iban.last(4)}" : nil ].compact.join(" ").presence || uid
  end

  # The booked balance at the end of the day, signed the bank's way (negative on a credit
  # card): the latest snapshot on or before the date, moved forward by the booked transactions
  # since it. Nil before the first snapshot; balances are never worked backwards.
  def balance_on(date)
    snapshot = balances.where(on: ..date).order(:on).last
    return unless snapshot

    snapshot.booked + bank_transactions.booked.where(occurred_on: (snapshot.on + 1)..date).sum(:amount)
  end

  def balance = balance_on(Date.current)
end
