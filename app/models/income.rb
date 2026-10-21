class Income < ApplicationRecord
  include OwnedByUser

  enum :source, {
    salary: 0,
    freelance: 1,
    business: 2,
    investment: 3,
    rental: 4,
    gift: 5,
    refund: 6,
    other: 7
  }

  enum :payment_method, {
    cash: 0,
    check: 1,
    bank_transfer: 2,
    direct_deposit: 3,
    other_payment_method: 4
  }

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :description, presence: true
  validates :received_on, presence: true
  validates :currency, presence: true

  scope :recurring, -> { where(recurring: true) }
  scope :between, ->(start_date, end_date) { where(received_on: start_date..end_date) }

  def self.total_for(start_date, end_date)
    between(start_date, end_date).sum(:amount)
  end
end
