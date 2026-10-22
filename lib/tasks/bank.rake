namespace :bank do
  desc "Fetch new transactions and today's balances for every account, like the daily job; ACCOUNT=5 for one account only"
  task sync: :environment do
    SyncBankTransactionsJob.perform_now(account_id: ENV["ACCOUNT"].presence&.to_i)
  end

  desc "Attach the accounts of every active connection again from its stored session (CONNECTION=3 for one), " \
       "adding the ones an older matching rule lost; existing accounts are kept"
  task attach_accounts: :environment do
    scope = ENV["CONNECTION"].present? ? BankConnection.where(id: ENV["CONNECTION"]) : BankConnection.active
    scope.find_each do |connection|
      before = connection.bank_accounts.count
      connection.reattach_accounts!
      puts "#{connection.aspsp_name} (#{connection.id}): #{connection.bank_accounts.count - before} account(s) added, " \
           "#{connection.bank_accounts.count} on the connection"
    end
  end
end

namespace :accounts do
  desc "Print an account's booked transactions in a range, oldest first, with the balance after each (read-only). ACCOUNT=5 FROM=2026-10-01 TO=2026-10-15"
  task transactions: :environment do
    account = BankAccount.find(ENV.fetch("ACCOUNT"))
    from = Date.iso8601(ENV.fetch("FROM"))
    to = ENV["TO"].present? ? Date.iso8601(ENV["TO"]) : Date.current
    names = TransactionCategory.pluck(:id, :name).to_h
    rows = account.bank_transactions.booked.where(occurred_on: from..to).order(:occurred_on, :id)
    pending = account.bank_transactions.pending.where(occurred_on: from..to).count
    running = account.balance_on(from - 1)

    puts "# #{account.display_name}: booked balance #{running&.to_s("F") || "unknown"} at the end of #{from - 1}, " \
         "#{account.balance_on(to)&.to_s("F") || "unknown"} at the end of #{to}; #{rows.count} booked rows, #{pending} pending left out"
    puts "# id, date, amount, counterparty, description, bank code, category, balance after"
    rows.each do |t|
      running += t.amount if running
      puts [ t.id, t.occurred_on, t.amount.to_s("F"), t.counterparty_name, t.description, t.bank_code,
             names[t.transaction_category_id], running&.to_s("F") ].map { |v| v.to_s.squish }.join("\t")
    end
  end

  desc "Print every account's latest balance snapshot, or with ON=2026-09-30 its balance at the end of that day (read-only)"
  task balances: :environment do
    if ENV["ON"].present?
      on = Date.iso8601(ENV["ON"])
      puts "# id, name, kind, booked balance on #{on} (the latest snapshot on or before it, moved by the transactions since)"
      BankAccount.order(:id).each do |account|
        puts [ account.id, account.display_name, account.credit_card? ? "credit card" : "account",
               account.balance_on(on)&.to_s("F") || "unknown" ].join("\t")
      end
    else
      puts "# id, name, kind, snapshot date, booked, available, credit limit"
      BankAccount.order(:id).each do |account|
        latest = account.balances.order(:on).last
        puts [ account.id, account.display_name, account.credit_card? ? "credit card" : "account",
               latest&.on, latest&.booked&.to_s("F") || "unknown", latest&.available&.to_s("F"),
               (account.credit_limit&.to_s("F") if account.credit_card?) ].join("\t")
      end
    end
  end
end
