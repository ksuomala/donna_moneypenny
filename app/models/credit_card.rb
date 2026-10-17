# A credit card: its transactions sync like any account's, and its booked balance is what we
# owe, so the stats page lists it with the loans. The bank reports the balance negative
# (money owed), which owed_on flips.
class CreditCard < BankAccount
  def credit_card? = true

  def owed_on(date)
    booked = balance_on(date)
    -booked if booked
  end

  def owed = owed_on(Date.current)

  # The card's limit, from the account details the bank gave when it was connected.
  def credit_limit
    amount = raw&.dig("credit_limit", "amount")
    BigDecimal(amount.to_s) if amount.present?
  end

  def creditor = bank_connection.aspsp_name
end
