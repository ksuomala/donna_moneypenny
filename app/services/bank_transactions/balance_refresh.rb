module BankTransactions
  class BalanceRefresh
    Result = Data.define(:updated, :unavailable)
    TIME_ZONE = "Europe/Helsinki"

    def initialize(users:, client_factory: ->(account) { EnableBanking::Client.for(account.bank_connection.enable_banking_app) }, conversion: Conversion.new)
      @users = Array(users)
      @client_factory = client_factory
      @conversion = conversion
    end

    def call
      updated = 0
      unavailable = []

      accounts.find_each do |account|
        next unless account.bank_connection&.usable?

        begin
          if record_balance(account)
            updated += 1
          else
            unavailable << account.display_name
          end
        rescue EnableBanking::Client::Error, ExchangeRates::Client::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError
          unavailable << account.display_name
        end
      end

      Result.new(updated:, unavailable:)
    end

    private

    def accounts = BankAccount.owned_by(@users).where(type: [ nil, BankAccount.sti_name, CreditCard.sti_name ]).where.not(bank_connection_id: nil)

    def record_balance(account)
      balances = @client_factory.call(account).balances(account_uid: account.uid)
      attributes = BankAccountBalance.attributes_from_api(balances)
      return false unless attributes

      today = Time.find_zone(TIME_ZONE).today
      currency = balances.first.dig("balance_amount", "currency") || account.currency
      snapshot = @conversion.balance(attributes, currency, today)
      account.balances.find_or_initialize_by(on: today).update!(snapshot)
      true
    end
  end
end
