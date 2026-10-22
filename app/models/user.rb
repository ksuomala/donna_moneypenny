# Someone who signs in. Each user has their own bank connections, categories, rules, loans and
# categorizer runs; accounts, transactions and balances belong to a user through a connection.
# Created with bin/rails users:create; there is no sign-up page.
class User < ApplicationRecord
  # The models with a user_id.
  OWNED_MODELS = %w[BankConnection TransactionCategory CategorizationRule CategorizationRun Loan Expense Income].freeze

  has_secure_password
  belongs_to :household, optional: true
  has_many :sessions, dependent: :destroy
  has_one :enable_banking_app, dependent: :destroy

  has_many :bank_connections
  has_many :bank_accounts, through: :bank_connections
  has_many :bank_transactions, through: :bank_accounts
  has_many :transaction_categories
  has_many :categorization_rules
  has_many :categorization_runs
  has_many :loans
  has_many :expenses
  has_many :incomes

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 12 }, allow_nil: true

  # The first user. Rake tasks and background jobs work on the owner's data until they run per user.
  def self.owner = order(:id).first

  # This user and the other members of their household, for the combined stats.
  def household_members
    household ? household.users.order(:id).to_a : [ self ]
  end

  # Gives this user every record that has no owner yet: the data from before there were users.
  # Fills in only, never moves a record from another user. Returns the count per model.
  def claim_unowned_records!
    transaction do
      OWNED_MODELS.to_h { |name| [ name, name.constantize.where(user_id: nil).update_all(user_id: id) ] }
    end
  end
end
