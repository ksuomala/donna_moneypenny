class TransactionCategory < ApplicationRecord
  include OwnedByUser

  belongs_to :parent, class_name: "TransactionCategory", optional: true
  has_many :children, class_name: "TransactionCategory", foreign_key: :parent_id, dependent: :restrict_with_error
  has_many :bank_transactions, dependent: :nullify
  has_many :categorization_rules, dependent: :restrict_with_error

  # Investments (e.g. rental properties) are tracked per sub-category: positive amounts are
  # revenue, negative ones costs. Categories excluded from stats (own transfers, credit card
  # payments, the home purchase) have no kind.
  enum :kind, { expense: 0, income: 1, investment: 3 }

  scope :in_stats, -> { where(exclude_from_stats: false) }

  KINDS = kinds.keys + [ "excluded" ]

  # Creates or updates a category by name (categories:upsert and categories:import). kind is
  # expense, income, investment or excluded (no kind, left out of stats). Attributes given as
  # nil keep their current value, so a description can be changed on its own. A new
  # sub-category takes its parent's kind unless one is given.
  def self.define!(name:, kind: nil, parent: nil, description: nil)
    category = find_or_initialize_by(name: name)
    category.parent = parent.is_a?(self) ? parent : find_by!(name: parent) unless parent.nil?
    if kind.nil? && category.new_record? && category.parent
      kind = category.parent.exclude_from_stats? ? "excluded" : category.parent.kind
    end
    unless kind.nil?
      raise ArgumentError, "kind must be one of #{KINDS.join(", ")}, not #{kind.inspect}" unless KINDS.include?(kind.to_s)
      category.exclude_from_stats = (kind.to_s == "excluded")
      category.kind = category.exclude_from_stats? ? nil : kind.to_s
    end
    category.description = description unless description.nil?
    category.save!
    category
  end

  # Defines categories from the categories:import format: a list of hashes with name, kind,
  # description and optional children (name, description). Nothing is deleted.
  def self.import!(definitions)
    transaction do
      definitions.flat_map do |attributes|
        parent = define!(name: attributes.fetch("name"), kind: attributes["kind"], description: attributes["description"])
        children = Array(attributes["children"]).map do |child|
          define!(name: child.fetch("name"), parent: parent, description: child["description"])
        end
        [ parent, *children ]
      end
    end
  end


  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :kind, presence: true, unless: :exclude_from_stats?
  validates :kind, absence: true, if: :exclude_from_stats?
  validate :at_most_two_levels
  validate :same_kind_as_parent

  private

  def default_owner
    parent&.user || super
  end

  def at_most_two_levels
    errors.add(:parent, "can't itself have a parent") if parent&.parent_id
    errors.add(:parent, "can't be set on a category with sub-categories") if parent && children.exists?
  end

  def same_kind_as_parent
    return unless parent

    errors.add(:kind, "must match the parent's kind") if kind != parent.kind
    errors.add(:exclude_from_stats, "must match the parent's") if exclude_from_stats != parent.exclude_from_stats
  end
end
