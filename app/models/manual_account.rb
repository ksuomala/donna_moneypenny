# An account kept by hand, like cash: no bank connection, so nothing syncs into it and it has
# no balance. Its transactions are added with record! (bin/rails transactions:create).
class ManualAccount < BankAccount
  validates :bank_connection, absence: true

  before_validation { self.uid ||= "manual-#{SecureRandom.uuid}" }

  def kind = "manual account"

  # A booked transaction in euros, optionally with a category of the account owner's.
  def record!(on:, amount:, counterparty: nil, description: nil, category: nil, dry_run: false)
    raise ArgumentError, "Category #{category.id} is another user's" if category && category.user_id != user_id

    transaction = bank_transactions.new(
      entry_reference: "manual-#{SecureRandom.uuid}",
      status: "booked",
      occurred_on: on,
      booking_date: on,
      amount: amount,
      currency: "EUR",
      counterparty_name: counterparty.presence,
      description: description.presence,
      transaction_category: category
    )
    dry_run ? transaction.validate! : transaction.save!
    transaction
  end
end
