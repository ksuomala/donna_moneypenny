class Expense < ApplicationRecord
  enum :category, {
    housing: 0,
    transportation: 1,
    food: 2,
    utilities: 3,
    insurance: 4,
    healthcare: 5,
    debt: 6,
    education: 7,
    entertainment: 8,
    personal: 9,
    other: 10
  }

  enum :payment_method, {
    cash: 0,
    credit_card: 1,
    debit_card: 2,
    bank_transfer: 3,
    check: 4,
    other_payment_method: 5
  }

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :description, presence: true
  validates :occurred_on, presence: true
  validates :currency, presence: true

  scope :recurring, -> { where(recurring: true) }
  scope :between, ->(start_date, end_date) { where(occurred_on: start_date..end_date) }

  def self.total_for(start_date, end_date)
    between(start_date, end_date).sum(:amount)
  end
end
