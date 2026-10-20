# Daily import of new bank transactions (scheduled in config/recurring.yml).
# Enable Banking has no webhooks for account data, so this polls. Banks typically allow
# about 4 unattended fetches per account per day, so don't schedule it more often than that.
class SyncBankTransactionsJob < ApplicationJob
  queue_as :default

  def perform
    failures = []

    BankConnection.active.includes(:bank_accounts).find_each do |connection|
      unless connection.valid_until.future?
        connection.expired!
        Rails.logger.warn("[bank sync] #{connection.aspsp_name} consent expired on #{connection.valid_until}; reconnect needed")
        next
      end

      connection.bank_accounts.each do |account|
        new_count = BankTransactions::Sync.new(account).call
        Rails.logger.info("[bank sync] #{account.display_name}: #{new_count} new booked transaction(s)")
      rescue StandardError => e
        failures << "#{account.display_name}: #{e.message}"
        Rails.logger.error("[bank sync] #{account.display_name} failed: #{e.message}")
      end
    end

    # Fail the job (visible in Solid Queue's failed executions) after trying every account.
    raise EnableBanking::Client::Error, "Bank sync failed for #{failures.size} account(s): #{failures.join('; ')}" if failures.any?
  ensure
    # The categorizer follows the sync, also when an account failed: the others' transactions are new.
    CategorizeTransactionsJob.perform_later
  end
end
