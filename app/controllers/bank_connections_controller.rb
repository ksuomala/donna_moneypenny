class BankConnectionsController < ApplicationController
  def index
    @connections = BankConnection.includes(bank_accounts: :bank_transactions).order(created_at: :desc)
  end
end
