module Api
  # The user's accounts. Bank accounts come from Enable Banking; only accounts kept by hand, like
  # cash (ManualAccount), are created here.
  class AccountsController < BaseController
    def index
      accounts = Current.user.bank_accounts.order(:id)
      render json: { accounts: accounts.map { |account| account_json(account) } }
    end

    def create
      account = ManualAccount.create!(user: Current.user, name: params.require(:name), currency: "EUR")
      render json: account_json(account), status: :created
    end

    private

    def account_json(account)
      { id: account.id, name: account.display_name, kind: account.kind, currency: account.currency, balance: account.balance }
    end
  end
end
