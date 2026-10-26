# Users who look at their finances together: the stats page can show their accounts combined
# (BankTransactions::Stats with several users). Members keep their own data; the household
# only says whose stats may be combined. Set up with bin/rails households:create.
class Household < ApplicationRecord
  has_many :users, dependent: :nullify
  has_many :budgets, dependent: :destroy

  validates :name, presence: true
end
