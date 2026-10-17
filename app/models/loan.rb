class Loan < ApplicationRecord
  has_many :balances, class_name: "LoanBalance", dependent: :destroy
  has_many :bank_transactions, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :creditor, :currency, presence: true

  # What we owe on a given day, or nil before the first balance we know of.
  #
  # Bank loans charge interest, so their balance comes only from recorded balances (e.g. from
  # loan statements). Interest-free private loans have balance_from_transactions set: their
  # balance is the latest recorded one plus every linked transaction booked after it, since
  # money received (positive) adds to the debt and payments (negative) reduce it.
  def balance_on(date)
    snapshot = balances.where(on: ..date).order(:on).last
    return unless snapshot
    return snapshot.balance unless balance_from_transactions?

    snapshot.balance + bank_transactions.booked.where(occurred_on: (snapshot.on + 1)..date).sum(:amount)
  end

  def balance
    balance_on(Date.current)
  end
end
