require "test_helper"

class BankConnectionTest < ActiveSupport::TestCase
  setup do
    @connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
  end

  def account(uid, type, hash: "h-#{uid}", **extra)
    { "uid" => uid, "identification_hash" => hash, "cash_account_type" => type, "product" => "Product", "currency" => "EUR" }.merge(extra)
  end

  test "card accounts become credit cards, the others plain accounts" do
    @connection.attach_account!(account("card", "CARD", "credit_limit" => { "amount" => "5000" }))
    @connection.attach_account!(account("acc", "CACC", "account_id" => { "iban" => "FI123" }))

    card = BankAccount.find_by!(uid: "card")
    assert_instance_of CreditCard, card
    assert_equal 5_000, card.credit_limit
    assert_instance_of BankAccount, BankAccount.find_by!(uid: "acc")
    assert_equal [ "acc" ], BankAccount.deposit.pluck(:uid)
  end

  test "currency pockets sharing one IBAN are separate accounts, matched by IBAN and currency on reconnect" do
    @connection.attach_account!(account("dkk", "CACC", hash: nil, "account_id" => { "iban" => "LT123" }, "currency" => "DKK"))
    @connection.attach_account!(account("eur", "CACC", hash: nil, "account_id" => { "iban" => "LT123" }, "currency" => "EUR"))
    @connection.attach_account!(account("eur-2", "CACC", hash: nil, "account_id" => { "iban" => "LT123" }, "currency" => "EUR"))

    assert_equal %w[DKK EUR], BankAccount.order(:currency).pluck(:currency)
    assert_equal "eur-2", BankAccount.find_by!(currency: "EUR").uid
  end

  test "reattaching from the stored session adds the accounts that were lost and keeps the rest" do
    dkk = account("dkk", "CACC", "account_id" => { "iban" => "LT123" }, "currency" => "DKK")
    eur = account("eur", "CACC", "account_id" => { "iban" => "LT123" }, "currency" => "EUR")
    @connection.update!(raw: { "accounts" => [ dkk, eur ] })
    @connection.attach_account!(eur)
    existing = BankAccount.find_by!(uid: "eur")

    @connection.reattach_accounts!

    assert_equal %w[dkk eur], @connection.bank_accounts.order(:uid).pluck(:uid)
    assert_equal existing, BankAccount.find_by!(uid: "eur")
  end

  test "reconnecting keeps the account's type" do
    @connection.attach_account!(account("card", "CARD"))
    @connection.attach_account!(account("card-2", "CARD", hash: "h-card"))

    assert_equal 1, BankAccount.count
    assert_instance_of CreditCard, BankAccount.find_by!(uid: "card-2")
  end
end
