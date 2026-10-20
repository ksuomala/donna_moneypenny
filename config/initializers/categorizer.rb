# The nightly categorizer (CategorizeTransactionsJob, BankTransactions::Categorizer). It starts
# in shadow mode: decisions are stored but not written to the transactions until
# CATEGORIZER_APPLY is set. Set the variables in config/deploy.yml (env.clear).
Rails.application.configure do
  # Reference rules (BankTransactions::Rules) are created, retired and applied after every sync.
  config.x.categorizer.rules = ActiveModel::Type::Boolean.new.cast(ENV.fetch("CATEGORIZER_RULES", "true"))
  config.x.categorizer.apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch("CATEGORIZER_APPLY", "false"))
  config.x.categorizer.model = ENV.fetch("CATEGORIZER_MODEL", "gpt-6-luna")
  # Reasoning effort for Claude and OpenAI models (Claude Haiku 4.5 and Jev take none).
  config.x.categorizer.effort = ENV.fetch("CATEGORIZER_EFFORT", "medium")
  # Jev (TypeSafe) answers with calibrated confidence; at or above this a choice counts as confident.
  config.x.categorizer.jev_confidence = Float(ENV.fetch("CATEGORIZER_JEV_CONFIDENCE", "0.9"))
  config.x.categorizer.batch_size = Integer(ENV.fetch("CATEGORIZER_BATCH_SIZE", "50"))
  config.x.categorizer.max_per_run = Integer(ENV.fetch("CATEGORIZER_MAX_PER_RUN", "500"))
  config.x.categorizer.cooldown_days = Integer(ENV.fetch("CATEGORIZER_COOLDOWN_DAYS", "7"))
end
