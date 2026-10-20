# A deterministic categorization: a transaction matching every condition the rule sets gets its
# category (and loan), before any model sees it. A rule must be precise: a reference, a
# reference prefix, or a counterparty together with an exact amount (the same rent or
# installment to the same person every month). A payee name alone can never be a rule. Derived rules are created from the owner's
# own history (BankTransactions::Rules.derive!); manual ones are set with rules:upsert, e.g.
# for loan installments whose reference changes every month but keeps a prefix.
class CategorizationRule < ApplicationRecord
  belongs_to :transaction_category
  belongs_to :loan, optional: true
  belongs_to :bank_account, optional: true
  has_many :bank_transactions, dependent: :nullify

  enum :source, { derived: 0, manual: 1 }
  enum :direction, { incoming: 0, outgoing: 1 }

  MIN_PREFIX = 8

  normalizes :reference, with: ->(value) { normalize_reference(value) }
  normalizes :reference_prefix, with: ->(value) { normalize_reference(value) }
  normalizes :counterparty, with: ->(value) { value.squish.presence }

  validate :names_a_reference
  validate :category_has_no_sub_categories
  validates :reference_prefix, length: { minimum: MIN_PREFIX }, allow_nil: true

  scope :active, -> { where(active: true) }
  # Manual rules first, then the more specific ones.
  scope :in_order, -> { order(source: :desc, bank_account_id: :desc, counterparty: :desc, id: :asc) }

  # Banks pad references with zeros and spaces differently: "0000 5550 001234" is 5550001234.
  def self.normalize_reference(value)
    value.to_s.gsub(/\s+/, "").sub(/\A0+(?=.)/, "").presence
  end

  def matches?(transaction)
    ref = self.class.normalize_reference(transaction.reference_number)
    return false if reference && ref != reference
    return false if reference_prefix && !ref.to_s.start_with?(reference_prefix)
    return false if bank_account_id && transaction.bank_account_id != bank_account_id
    return false if counterparty && transaction.counterparty_name.to_s.squish.casecmp(counterparty) != 0
    return false if amount && transaction.amount != amount
    return false if incoming? && transaction.amount.negative?
    return false if outgoing? && transaction.amount.positive?

    true
  end

  def describe
    [ ("ref #{reference}" if reference), ("ref #{reference_prefix}…" if reference_prefix), ("account #{bank_account_id}" if bank_account_id),
      ("from/to #{counterparty}" if counterparty), ("amount #{amount.to_s("F")}" if amount), direction ].compact.join(", ")
  end

  def disable!(reason)
    update!(active: false, disabled_reason: reason.first(250))
  end

  private

  def names_a_reference
    precise = reference.present? || reference_prefix.present? || (counterparty.present? && amount.present?)
    errors.add(:base, "needs a reference, a reference prefix, or a counterparty with an exact amount") unless precise
    errors.add(:base, "takes a reference or a prefix, not both") if reference.present? && reference_prefix.present?
  end

  def category_has_no_sub_categories
    errors.add(:transaction_category, "must be a sub-category") if transaction_category&.children&.exists?
  end
end
