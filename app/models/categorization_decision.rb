# What the categorizer decided for one transaction in one run, after the guardrails
# (BankTransactions::Categorizer). applied says whether the category was written to the
# transaction; guard names the guardrail that turned a confident decision into an unsure one.
class CategorizationDecision < ApplicationRecord
  belongs_to :run, class_name: "CategorizationRun", foreign_key: :categorization_run_id, inverse_of: :decisions
  belongs_to :bank_transaction
  belongs_to :transaction_category, optional: true
  belongs_to :loan, optional: true

  enum :confidence, { unsure: 0, confident: 1 }
end
