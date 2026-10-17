# A loan's balance on a given day: entered from a loan statement, or the starting point of an
# interest-free loan whose balance then follows its transactions.
class LoanBalance < ApplicationRecord
  belongs_to :loan

  validates :on, presence: true, uniqueness: { scope: :loan_id }
  validates :balance, presence: true, numericality: true
end
