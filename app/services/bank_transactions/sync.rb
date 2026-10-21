module BankTransactions
  # Fetches an account's transactions and balances from Enable Banking and stores them.
  #
  # Booked transactions are upserted by entry_reference, so re-fetching is harmless.
  # Pending ones are replaced as a set on every sync: Nordea may give a transaction a new
  # entry_reference once it's booked, and cancelled card holds simply disappear.
  # Balances are kept as one snapshot per account per day; syncing again the same day
  # replaces that day's snapshot.
  class Sync
    # First sync goes as far back as the bank allows (current accounts returned ~5 months,
    # the credit card ~7 weeks when this was written).
    INITIAL_LOOKBACK = 1.year
    # Later syncs re-fetch this far behind the newest booked transaction, to catch
    # late-posted and back-dated entries.
    OVERLAP = 14.days
    MAX_PAGES = 100
    # The day a balance snapshot is filed under: the sync runs in the evening Helsinki time.
    TIME_ZONE = "Europe/Helsinki"

    # The client defaults to the app the account's connection was made with: the session is
    # bound to that app, so only its key can read the account.
    def initialize(bank_account, client: bank_account.bank_connection.enable_banking_app&.client)
      @account = bank_account
      @client = client
    end

    # Returns the number of transactions that were new to us. Transactions are saved before
    # the balances are fetched, so a failed balances request loses nothing but the snapshot.
    def call
      transactions = fetch_all(date_from)
      before = @account.bank_transactions.booked.count

      BankTransaction.transaction do
        @account.bank_transactions.pending.delete_all
        rows = with_references(transactions).map { |t| BankTransaction.attributes_from_api(t).merge(bank_account_id: @account.id) }
        # MySQL upserts on the unique (bank_account_id, entry_reference) index.
        BankTransaction.upsert_all(rows, record_timestamps: true) if rows.any?
        @account.update!(last_synced_at: Time.current)
      end

      record_balances

      @account.bank_transactions.booked.count - before
    end

    private

    def date_from
      latest = @account.bank_transactions.booked.maximum(:booking_date)
      latest ? latest - OVERLAP : INITIAL_LOOKBACK.ago.to_date
    end

    # Today's snapshot. Nothing is recorded when the bank reports no booked balance, so the
    # account shows as unknown rather than zero.
    def record_balances
      attributes = BankAccountBalance.attributes_from_api(@client.balances(account_uid: @account.uid))
      return unless attributes

      @account.balances.find_or_initialize_by(on: Time.find_zone(TIME_ZONE).today).update!(attributes)
    end

    # Nordea occasionally omits entry_reference (seen on a pending row). Those get a stable
    # fingerprint instead; identical fingerprints within one fetch are numbered apart.
    def with_references(transactions)
      seen = Hash.new(0)

      transactions.map do |transaction|
        next transaction if transaction["entry_reference"].present?

        fingerprint = "fp:" + Digest::SHA256.hexdigest(transaction.values_at(
          "booking_date", "transaction_date", "transaction_amount", "credit_debit_indicator",
          "creditor", "debtor", "remittance_information", "reference_number"
        ).to_json).first(40)
        seen[fingerprint] += 1

        transaction.merge("entry_reference" => seen[fingerprint] > 1 ? "#{fingerprint}-#{seen[fingerprint]}" : fingerprint)
      end
    end

    def fetch_all(from)
      transactions = []
      continuation_key = nil

      MAX_PAGES.times do
        page = @client.transactions(account_uid: @account.uid, date_from: from, continuation_key: continuation_key)
        transactions.concat(page.fetch("transactions", []))
        continuation_key = page["continuation_key"]
        return transactions if continuation_key.blank?
      end

      raise EnableBanking::Client::Error, "Too many pages of transactions for account #{@account.id}"
    end
  end
end
