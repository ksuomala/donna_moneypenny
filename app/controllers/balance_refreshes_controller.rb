class BalanceRefreshesController < ApplicationController
  def create
    users = params[:scope] == "household" && Current.user.household ? Current.user.household_members : [ Current.user ]
    result = BankTransactions::BalanceRefresh.new(users:).call

    message = "Updated balances for #{result.updated} account(s)."
    message += " Could not refresh: #{result.unavailable.join(", ")}." if result.unavailable.any?
    redirect_to stats_path(scope: params[:scope] == "household" ? "household" : "me"), notice: message
  end
end
