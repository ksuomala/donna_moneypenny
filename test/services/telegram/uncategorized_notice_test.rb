require "test_helper"

class Telegram::UncategorizedNoticeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(telegram_chat_id: "111")
    connection = BankConnection.create!(user: @user, session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", currency: "EUR")
    @groceries = TransactionCategory.create!(user: @user, name: "Groceries", kind: :expense)
  end

  def txn(counterparty, amount: -23.4, **attributes)
    @account.bank_transactions.create!(entry_reference: SecureRandom.hex(4), occurred_on: Date.new(2026, 11, 4), amount: amount,
                                       currency: "EUR", counterparty_name: counterparty, **attributes)
  end

  def guess(transaction, category)
    run = CategorizationRun.create!(user: @user, mode: :apply, model: "claude-test", prompt_version: "v", rules_digest: "d", started_at: Time.current)
    run.decisions.create!(bank_transaction: transaction, transaction_category: category, confidence: :unsure, reason: "maybe")
  end

  test "lists the uncategorized booked rows with their ids and guesses, once" do
    shop = txn("K-Market <Kamppi>")
    steam = txn(nil, amount: -12.99, description: "PAYPAL *STEAM  games")
    txn("Done", transaction_category: @groceries)
    txn("Pending", status: :pending)
    guess(shop, @groceries)

    TelegramStub.with do |stub|
      Telegram::UncategorizedNotice.new(@user).send!(client: stub)
      text = stub.messages.sole.text

      assert_equal "111", stub.messages.sole.chat_id
      assert_includes text, "<b>2 transactions I couldn’t categorize</b>"
      assert_includes text, "<code>##{shop.id}</code> · 4 Nov · K-Market &lt;Kamppi&gt; · −23,40 € · Groceries?"
      assert_includes text, "<code>##{steam.id}</code> · 4 Nov · PAYPAL *STEAM games · −12,99 €\n"
      assert_includes text, "e.g. “#{shop.id} Groceries”"
      assert_not_includes text, "Done"
      assert_not_includes text, "Pending"
      assert_not_includes text, "older"
      assert [ shop, steam ].all? { |t| t.reload.uncategorized_notified_at }

      Telegram::UncategorizedNotice.new(@user).send!(client: stub)
      assert_equal 1, stub.messages.size, "listed again"

      txn("New")
      Telegram::UncategorizedNotice.new(@user).send!(client: stub)
      assert_includes stub.messages.last.text, "<b>1 transaction I couldn’t categorize</b>"
      assert_includes stub.messages.last.text, "2 older ones are still uncategorized."
    end
  end

  test "lists at most LIMIT and says how many wait for the next message" do
    (Telegram::UncategorizedNotice::LIMIT + 2).times { |i| txn("Shop #{i}") }

    text = Telegram::UncategorizedNotice.new(@user).text

    assert_includes text, "…and 2 more, listed next time"
    assert_equal Telegram::UncategorizedNotice::LIMIT, Telegram::UncategorizedNotice.new(@user).due.size
  end

  test "sends nothing and marks nothing without a chat or a failed send" do
    shop = txn("K-Market")
    @user.update!(telegram_chat_id: nil)
    TelegramStub.with { |stub| assert_empty Telegram::UncategorizedNotice.new(@user).send!(client: stub); assert_empty stub.messages }
    assert_nil shop.reload.uncategorized_notified_at

    @user.update!(telegram_chat_id: "111")
    assert_raises(Telegram::Client::Error) do
      Telegram::UncategorizedNotice.new(@user).send!(client: TelegramStub.new(raises: Telegram::Client::Error.new("down")))
    end
    assert_nil shop.reload.uncategorized_notified_at
  end
end
