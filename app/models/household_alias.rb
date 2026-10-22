# A name a user appears under as a counterparty on another household member's account, e.g.
# "JANE MARIE DOE", "Jane Mobile" or "MobilePay Jane Marie Doe". Matched as a
# whole, case-insensitively, anywhere in the counterparty name. The household stats leave out
# every transaction whose counterparty is another member (BankTransactions::Stats).
# Managed with bin/rails households:alias.
class HouseholdAlias < ApplicationRecord
  belongs_to :user

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }

  # Whether a counterparty name is one of these aliases.
  def self.match?(counterparty, aliases)
    return false if counterparty.blank?

    needle = counterparty.squish.downcase
    aliases.any? { |name| needle.include?(name.downcase) }
  end
end
