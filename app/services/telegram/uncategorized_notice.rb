module Telegram
  # Lists a user's booked transactions that are still without a category after the categorizer's
  # run, each one once (bank_transactions.uncategorized_notified_at), with the transaction id and
  # the categorizer's guess so the owner can answer by id (Hermes fills them in with
  # transactions:categorize). Goes to the user's own chat, not the household's. Sending and
  # recording happen together, so a failed send lists the same rows the next time.
  class UncategorizedNotice
    LIMIT = 30

    attr_reader :user

    def initialize(user)
      @user = user
    end

    def uncategorized = user.bank_transactions.booked.where(transaction_category_id: nil)

    # The ones not listed yet, oldest first, at most LIMIT; the rest wait for the next notice.
    def due = uncategorized.where(uncategorized_notified_at: nil).order(:occurred_on, :id).limit(LIMIT).to_a

    # Sends when anything is due and the user has a chat; returns the messages as Telegram
    # describes them.
    def send!(client: Client.for)
      transactions = due
      chats = Chats.for(user)
      return [] if transactions.empty? || chats.empty?

      message = text(transactions)
      BankTransaction.transaction do
        BankTransaction.where(id: transactions.map(&:id)).update_all(uncategorized_notified_at: Time.current)
        chats.map { |chat_id| client.send_message(chat_id: chat_id, text: message) }
      end
    end

    def text(transactions = due)
      guesses = CategorizationDecision.where(bank_transaction_id: transactions.map(&:id)).order(:id)
        .includes(:transaction_category).index_by(&:bank_transaction_id)
      waiting = uncategorized.where(uncategorized_notified_at: nil).count - transactions.size
      older = uncategorized.where.not(uncategorized_notified_at: nil).count

      lines = [ Format.bold("#{transactions.size} #{"transaction".pluralize(transactions.size)} I couldn’t categorize") ]
      lines += transactions.map { |t| line(t, guesses[t.id]&.transaction_category) }
      lines << "…and #{waiting} more, listed next time" if waiting.positive?
      lines << "" << "Reply with the categories, e.g. “#{transactions.first.id} Groceries”."
      lines << "#{older} older #{older == 1 ? "one is" : "ones are"} still uncategorized." if older.positive?
      lines.join("\n")
    end

    private

    def line(transaction, guess)
      name = transaction.counterparty_name.presence || transaction.description.to_s.squish.truncate(40)
      parts = [ "<code>##{transaction.id}</code>", transaction.occurred_on.strftime("%-d %b"), Format.escape(name), Format.signed_money(transaction.amount) ]
      parts << "#{Format.escape(guess.name)}?" if guess
      parts.join(" · ")
    end
  end
end
