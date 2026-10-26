require "test_helper"

class BankTransactionTest < ActiveSupport::TestCase
  test "bank code is the bank's description, or its code when there is no description" do
    assert_equal "Oma siirto", BankTransaction.new(raw: { "bank_transaction_code" => { "code" => "TRANSFER", "description" => "Oma siirto" } }).bank_code
    assert_equal "TOPUP", BankTransaction.new(raw: { "bank_transaction_code" => { "code" => "TOPUP", "description" => nil } }).bank_code
    assert_nil BankTransaction.new(raw: { "bank_transaction_code" => nil }).bank_code
    assert_nil BankTransaction.new(raw: nil).bank_code
  end
end
