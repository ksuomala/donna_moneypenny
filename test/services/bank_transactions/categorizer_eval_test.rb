require "test_helper"

class BankTransactions::CategorizerEvalTest < ActiveSupport::TestCase
  setup do
    connection = BankConnection.create!(session_id: "s", aspsp_name: "Nordea", aspsp_country: "FI", valid_until: 1.month.from_now)
    @account = connection.bank_accounts.create!(uid: "acc-1", name: "Käyttötili", currency: "EUR")
    @groceries = TransactionCategory.create!(name: "Groceries", kind: :expense)
    @cafes = TransactionCategory.create!(name: "Cafes", kind: :expense)
  end

  def transaction(ref, counterparty, category, **attributes)
    @account.bank_transactions.create!(entry_reference: ref, status: "booked", occurred_on: Date.new(2026, 10, 1), amount: -12.5,
                                       currency: "EUR", counterparty_name: counterparty, transaction_category: category, **attributes)
  end

  test "sends categorized transactions as new without their own decisions, reports precision and writes nothing" do
    shop = transaction("a", "K-Market", @groceries)
    cafe = transaction("b", "Cafe", @cafes)
    transaction("old", "Cafe", @cafes, occurred_on: Date.new(2025, 1, 1))
    transaction("open", "Other", nil)
    theirs = BankConnection.create!(user: User.where.not(id: User.owner.id).first, session_id: "s2", aspsp_name: "Revolut", aspsp_country: "LT", valid_until: 1.month.from_now)
    theirs.bank_accounts.create!(uid: "acc-2", currency: "EUR").bank_transactions
      .create!(entry_reference: "t", status: "booked", occurred_on: Date.new(2026, 10, 1), amount: -1, currency: "EUR", counterparty_name: "Netto", transaction_category: @cafes)
    contexts = []
    # Groceries for everything: right for the shop, wrong for the cafe.
    client = CategorizerStub.new do |ids|
      ids.map { |id| { transaction_id: id, category_id: @groceries.id, loan_id: nil, confidence: "confident", reason: "guess" } }
    end
    client.define_singleton_method(:create) { |**params| contexts << params[:system_].second[:text]; super(**params) }

    eval = CategorizerStub.with(client) { BankTransactions::CategorizerEval.new(sample: 10, since: Date.new(2026, 1, 1), batch_size: 1, model: "claude-haiku-4-5").call }

    assert_equal [ shop.id, cafe.id ].sort, eval.rows.map { |r| r.transaction.id }.sort
    assert contexts.all? { |text| !text.include?("K-Market\t") }
    assert contexts.all? { |text| text.include?("Cafe\t#{@account.id}\tCafes\t1") }
    report = eval.report
    assert_includes report, "all\t2\t2\t1\t50.0%\t0/0"
    assert_includes report, "with precedent\t1\t1\t0\t0.0%"
    assert_includes report, "without precedent\t1\t1\t1\t100.0%"
    assert_includes report, "#{cafe.id}\t2026-10-01\t-12.5\tCafe\t\tCafes\tGroceries\tguess"
    run = eval.run
    assert run.eval?
    assert run.finished?
    assert_equal [ 2, 2 ], [ run.decisions.count, run.confident_count ]
    assert_equal @cafes, cafe.reload.transaction_category
    assert_equal 0, run.decisions.where(applied: true).count
  end
end
