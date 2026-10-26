class BankConnectionsController < ApplicationController
  def index
    @connections = Current.user.bank_connections.includes(bank_accounts: :bank_transactions).order(created_at: :desc)
  end
end
