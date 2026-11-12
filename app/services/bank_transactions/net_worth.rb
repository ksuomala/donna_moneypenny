module BankTransactions
  class NetWorth
    Result = Data.define(:assets, :liabilities, :unknown_balance_count) do
      def amount = assets - liabilities
    end

    def initialize(users:)
      @users = Array(users)
      raise ArgumentError, "Net worth needs at least one user" if @users.empty?
    end

    def call
      today = Time.find_zone("Europe/Helsinki").today
      asset_accounts = BankAccount.owned_by(@users).where(type: [ nil, "BankAccount", "ManualAccount" ])
      cards = BankAccount.owned_by(@users).where(type: CreditCard.sti_name)

      account_balances = asset_accounts.map { |account| account.balance_on(today) }
      assets = account_balances.compact.sum(BigDecimal(0))
      aliases_by_user = HouseholdAlias.where(user: @users).pluck(:user_id, :name).group_by(&:first).transform_values { |rows| rows.map(&:last) }
      loans = Loan.where(user: @users).reject do |loan|
        other_aliases = aliases_by_user.except(loan.user_id).values.flatten
        @users.many? && HouseholdAlias.match?(loan.creditor, other_aliases)
      end
      loan_balances = loans.map { |loan| loan.balance_on(today) }
      card_balances = cards.map { |card| card.owed_on(today) }
      liabilities = loan_balances.compact.sum(BigDecimal(0)) + card_balances.compact.sum(BigDecimal(0))

      Result.new(assets:, liabilities:, unknown_balance_count: (account_balances + loan_balances + card_balances).count(&:nil?))
    end
  end
end
