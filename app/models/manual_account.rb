# An account kept by hand, like cash: no bank connection, so nothing syncs into it. Its
# transactions are added with record! (bin/rails transactions:create) and its balance is what
# was counted (record_balance!, bin/rails accounts:record_balance).
class ManualAccount < BankAccount
  validates :bank_connection, absence: true

  before_validation { self.uid ||= "manual-#{SecureRandom.uuid}" }

  def kind = "manual account"

  # The latest count on or before the date, not moved by transactions: withdrawals land on the
  # bank accounts, not here, so the logged rows alone can't carry a balance forward.
  def balance_on(date)
    balances.where(on: ..date).order(:on).last&.booked
  end

  # Replaces a count recorded for the same day.
  def record_balance!(on:, balance:, dry_run: false)
    count = balances.find_or_initialize_by(on: on)
    count.assign_attributes(booked: balance, booked_type: "counted")
    dry_run ? count.validate! : count.save!
    count
  end

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
