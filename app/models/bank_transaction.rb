class BankTransaction < ApplicationRecord
  belongs_to :bank_account
  belongs_to :transaction_category, optional: true
  belongs_to :loan, optional: true

  enum :status, { booked: 0, pending: 1 }

  validate :category_has_no_sub_categories

  # Maps one Enable Banking transaction to our columns. Amounts are signed:
  # money out (DBIT) is negative, money in (CRDT) positive.
  def self.attributes_from_api(transaction)
    debit = transaction["credit_debit_indicator"] == "DBIT"
    amount = BigDecimal(transaction.dig("transaction_amount", "amount").to_s)
    counterparty = debit ? transaction["creditor"] : transaction["debtor"]

    {
      entry_reference: transaction.fetch("entry_reference"),
      status: transaction["status"] == "PDNG" ? "pending" : "booked",
      occurred_on: transaction["booking_date"] || transaction["transaction_date"] || transaction["value_date"],
      booking_date: transaction["booking_date"],
      transaction_date: transaction["transaction_date"],
      value_date: transaction["value_date"],
      amount: debit ? -amount.abs : amount.abs,
      currency: transaction.dig("transaction_amount", "currency"),
      counterparty_name: counterparty&.dig("name").presence,
      description: Array(transaction["remittance_information"]).compact_blank.join(" ").presence,
      reference_number: transaction["reference_number"].presence,
      merchant_category_code: transaction["merchant_category_code"].presence,
      raw: transaction
    }
  end

  private

  # Categories with sub-categories (like Investment) only group them; transactions go on a sub-category.
  def category_has_no_sub_categories
    errors.add(:transaction_category, "must be a sub-category") if transaction_category&.children&.exists?
  end
end
