# A monthly spending budget for a user or a household: an optional total and amounts per
# category (BudgetLine, by category name, so a household budget covers the members' categories
# of the same name). It applies from starts_on, until ends_on if set. The stats page shows the
# budget that applies to the period shown (BudgetReport), monthly amounts prorated to it.
class Budget < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :household, optional: true
  has_many :lines, class_name: "BudgetLine", dependent: :destroy

  validates :starts_on, presence: true
  validates :monthly_total, numericality: { greater_than: 0 }, allow_nil: true
  validate :one_owner
  validate :ends_after_start

  scope :for_owner, ->(owner) { owner.is_a?(Household) ? where(household: owner) : where(user: owner) }

  # The budget in force for a period: the latest-starting one whose window overlaps it.
  def self.applying_to(owner, range)
    for_owner(owner).where(starts_on: ..range.end).where("ends_on IS NULL OR ends_on >= ?", range.begin).order(starts_on: :desc).first
  end

  def owner = household || user

  # The part of a period this budget covers, or nil when it covers none of it.
  def covered(range)
    from = [ range.begin, starts_on ].max
    to = [ range.end, ends_on ].compact.min
    from..to if from <= to
  end

  # How many months a period is: each calendar month counts by the share of its days in the
  # period, so a full month is 1, a week about 0.23 and a year 12.
  def self.months_in(range)
    month = range.begin.beginning_of_month
    total = 0.0
    while month <= range.end
      overlap = [ range.begin, month ].max..[ range.end, month.end_of_month ].min
      total += (overlap.end - overlap.begin + 1).to_f / month.end_of_month.day
      month = month.next_month
    end
    total.round(4)
  end

  # Replaces the lines with the given category name => monthly amount pairs; blank or zero
  # amounts drop the line.
  def lines_attributes=(pairs)
    @pending_lines = pairs.to_h.filter_map do |name, amount|
      amount = BigDecimal(amount.to_s.tr(",", "."), exception: false)
      [ name.to_s.squish, amount ] if name.present? && amount&.positive?
    end
  end

  after_save :write_pending_lines

  private

  def one_owner
    errors.add(:base, "A budget belongs to a user or a household") unless [ user, household ].compact.one?
  end

  def ends_after_start
    errors.add(:ends_on, "must be after the start") if ends_on && starts_on && ends_on < starts_on
  end

  def write_pending_lines
    return if @pending_lines.nil?

    lines.where.not(category_name: @pending_lines.map(&:first)).delete_all
    @pending_lines.each { |name, amount| lines.find_or_initialize_by(category_name: name).update!(monthly_amount: amount) }
    lines.reset
    @pending_lines = nil
  end
end
