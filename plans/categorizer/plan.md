# Categorizer: automatic transaction categorization with Claude

Brief: none. Stages 1-2 were done in conversation on 2026-10-20; the alignment is summarized below.
Issue: none

What was aligned:
- Categorization must use **all fields** of a transaction together (account, date, amount, counterparty, description, reference, MCC, bank code). The counterparty is a signal, never a rule. The recipient approach was tried and dropped.
- The category descriptions in the database are the rules. Earlier decisions are precedent.
- Precision over coverage: an uncategorized transaction is harmless, a wrong one skews every report. Never re-categorize.
- Writes go only through `BankTransactions::Categorization.apply` / `link_loans` (fill missing only, booked only, leaf categories only).
- No personal data from production in the repo. Prompt text committed to git must be generic.
- Tool: the official `anthropic` Ruby gem, one Messages API request per batch of rows, structured outputs. No agent loop, no Make, no Managed Agents, no Batches API (not needed for nightly volumes).

## Context

Today the categorize-transactions skill (an interactive Claude Code session) reads context and the backlog through rake tasks, decides, previews and writes. This plan moves the deciding into the app: a nightly job sends each batch of uncategorized booked transactions to Claude with the same context the skill uses, stores every decision, and applies only the confident ones through the existing guards. Unsure decisions are kept with the model's best guess and reason, so the skill (or the owner) handles only those. The job starts in shadow mode (decide, store, don't write) and is switched on after a blind evaluation against transactions already categorized shows the confident bucket is precise.

## Design

### Service: `app/services/bank_transactions/categorizer.rb`

`BankTransactions::Categorizer.new(context, client:)` → `#call(transactions)` decides one batch (default 50 rows) and returns decisions plus usage.

Request, verified against anthropic-sdk-ruby 1.80.0:
```ruby
client.messages.create(
  model: "claude-opus-5-5", max_tokens: 16_000,
  system_: [
    { type: "text", text: generic_prompt,  cache_control: { type: "ephemeral" } },
    { type: "text", text: runtime_context, cache_control: { type: "ephemeral" } }
  ],
  messages: [{ role: "user", content: batch_text }],
  output_config: { effort: "medium", format: Decisions },
  request_options: { timeout: 600, max_retries: 3 }
)
```
- Thinking stays adaptive (the default). Opus by default per the API guidance; Sonnet 5.5 is a one-line change the eval task can measure.
- **System block 1, generic instructions**: `app/services/bank_transactions/categorizer/prompt.md`, committed, no personal data. Holds the role, the output contract (one decision per row, reason ≤ 20 words), the "signals, strongest first" and "rules that are easy to get wrong" sections that live in SKILL.md today (moved here; the skill then references this file instead of repeating them), and the confidence definition: confident = description and data agree, anything else unsure with a best guess.
- **System block 2, runtime context**: built once per run, identical for every batch so it is read from cache from the second batch on: `Categorization.context` output (categories with descriptions, loans, accounts, known counterparty decisions).
- **User message**: the batch as TSV with the columns `Categorization.uncategorized` prints, plus per-row **pairing hints** computed in code: booked *and pending* rows on other accounts with the same absolute amount and opposite sign within ±5 days (id, account, date, amount, counterparty, bank code, category if any); for card payments, `Suoritus` rows on the card account. No raw history dump.

Structured output, typed (`nil?: true` is the SDK's nullable; `optional` is not):
```ruby
class Decision < Anthropic::BaseModel
  required :transaction_id, Integer
  required :category_id, Integer, nil?: true, doc: "leaf category id, or null when unsure which"
  required :loan_id, Integer, nil?: true, doc: "only for Loans, the loan's id"
  required :confidence, Anthropic::EnumOf[:confident, :unsure]
  required :reason, String
end
class Decisions < Anthropic::BaseModel
  required :decisions, Anthropic::ArrayOf[Decision]
end
```
`message.parsed_output` is a `Decisions` on success and a Hash with `error` when the JSON was cut off, so the service checks `stop_reason` and `parsed_output.is_a?(Decisions)` before reading.

Response handling and guardrails (code, independent of the model):
- `stop_reason == :max_tokens` → raise `BatchTruncated`; the job retries that batch split in two. `:refusal` → recorded on the run, batch skipped.
- Decisions for ids not in the batch are dropped; on duplicate ids the first wins; rows the model left out get an unsure decision with reason "no decision".
- `category_id` unknown or a parent category → unsure, guard "invalid category".
- `confident` with |amount| > 1 000 and no exact precedent (same counterparty + account + category among known decisions) → unsure, guard "large amount without precedent".
- `confident` Own with no pairing hint and bank code other than `Oma siirto` → unsure, guard "own transfer without other side".
- `loan_id` kept only when the category is Loans and the loan exists.
- Usage (`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`) returned with the decisions.

Client: `Categorizer.client_factory` class attribute like `EnableBanking::Client.factory`, default `-> { Anthropic::Client.new(api_key: Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]) }`, built lazily (the client needs a key at construction). Tests swap in a stub returning `Struct(stop_reason:, parsed_output:, usage:)`. No recorded responses, no VCR.

The refusal-fallback beta is left out of v1 (it would move the call to `client.beta.messages.create`; structured outputs work there too, so it can be added later).

### Persistence

Two tables: decisions outlive runs, unsure ones are reviewable, evals are repeatable, cost is visible, and the cooldown below needs history.
- `categorization_runs`: mode (`shadow`/`apply`/`eval`), model, prompt_version (SHA of prompt.md), rules_digest (SHA of category names + descriptions), started_at, finished_at, transactions_count, confident_count, unsure_count, applied_count, input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens, error.
- `categorization_decisions`: run_id, bank_transaction_id, transaction_category_id (nullable, FK nullify), loan_id (nullable), confidence (enum), reason, guard (nullable string), applied (boolean). Unique (run_id, bank_transaction_id), index on bank_transaction_id.

Models `CategorizationRun` (has_many :decisions) and `CategorizationDecision`; `BankTransaction has_many :categorization_decisions`.

### Job: `app/jobs/categorize_transactions_job.rb`

- Enqueued from the `ensure` of `SyncBankTransactionsJob#perform`, so it runs after the sync even when an account failed, and in order (a recurring entry 30 minutes later could race a slow sync).
- `limits_concurrency to: 1, key: "categorizer"`. The rake task enqueues with `perform_later` for real runs so the limit applies; `perform_now` only for `DRY_RUN`.
- **One job per batch, self-re-enqueuing with `run_id`**: the first job creates the run and the batch plan; each job decides one batch, stores its decisions, applies if in apply mode, updates the run counters, and enqueues the next batch. Solid Queue runs inside Puma and gets about five seconds on a Kamal restart, so no job may run for minutes. `finished_at`/`error` are set in `ensure`; a failed batch ends the run with its error, earlier batches stay stored.
- Selection: oldest uncategorized booked transactions, capped by `max_per_run` (default 500), **minus rows on cooldown**: a row whose latest decision is unsure is re-sent only when the rules digest changed (a description was edited, which is how the owner answers questions) or `cooldown_days` (default 7) have passed. Without this the cap fills with the same permanently-unsure rows every night.
- Apply mode: confident decisions go through `Categorization.apply`; Loans ones with a loan through `link_loans`; `applied` set per decision from the results. Shadow mode stores only.
- `Anthropic::Errors::RateLimitError` → re-enqueue the batch with a delay; other API errors end the run with the error recorded.
- Config `config/initializers/categorizer.rb` from env with defaults: `CATEGORIZER_APPLY` (false), `CATEGORIZER_MODEL` (claude-opus-5-5), `CATEGORIZER_BATCH_SIZE` (50), `CATEGORIZER_MAX_PER_RUN` (500), `CATEGORIZER_COOLDOWN_DAYS` (7). Kamal `env.clear` carries them; the API key goes into Rails credentials (`anthropic: api_key:`), already shipped via `RAILS_MASTER_KEY`.

### Rake tasks: `lib/tasks/categorizer.rake`

- `transactions:categorizer_run [LIMIT=] [DRY_RUN=1]` — enqueue a run now (shadow unless config apply); `DRY_RUN=1` runs one batch inline, prints the decisions, stores nothing.
- `transactions:unsure [RUN=id]` — the latest (or given) run's unsure decisions as the table the skill reports: date, amount, counterparty, description, guess, reason, guard, grouped by counterparty. The skill starts here.
- `transactions:categorizer_runs` — runs with mode, counts, tokens, cache reads, estimated cost, error.
- `transactions:categorizer_eval SAMPLE=200 [SINCE=2026-01-01]` — blind evaluation, inline: a random sample of booked categorized rows is sent as if uncategorized. Leak-proof context: `Categorization.context(excluding: ids)` drops the sampled rows from the known-counterparty counts, and pairing hints show sampled rows without their category. Compares decisions with the truth; prints precision and coverage per confidence bucket, split into "had precedent outside the sample" and "no precedent", a per-category confusion list, and every wrong confident decision row by row. Stored as a run with mode `eval`, never applied.

### Changes to `Categorization` (`app/services/bank_transactions/categorization.rb`)

- `context(excluding: [])` and an extracted `known_decisions(excluding:)` (counterparty, account, category, count) reused by context, the large-amount guardrail and the eval.
- `pairing_hints(transactions)` for the candidate-pair lookup.
- `apply`/`link_loans` unchanged.

### Skill and docs

- `SKILL.md`: the signals and pitfalls move to `prompt.md`, which the skill tells the agent to read. New workflow: the nightly job does the bulk; the skill starts from `transactions:unsure`, asks the grouped questions, writes answers into category descriptions (which lifts the cooldown), runs `categorizer_eval` after rule changes, and keeps the manual `transactions:uncategorized`/`categorize` path for when the job is off.
- README: short "automatic categorization" section (shadow mode, eval, switching apply on). todo.md: tick the item. `CLAUDE.md`: one line naming `prompt.md` and test data as places that must stay generic.

## Files

New: `app/services/bank_transactions/categorizer.rb`, `app/services/bank_transactions/categorizer/prompt.md`, `app/models/categorization_run.rb`, `app/models/categorization_decision.rb`, `db/migrate/<ts>_create_categorization_runs_and_decisions.rb`, `app/jobs/categorize_transactions_job.rb`, `config/initializers/categorizer.rb`, `lib/tasks/categorizer.rake`, `test/services/bank_transactions/categorizer_test.rb`, `test/jobs/categorize_transactions_job_test.rb`, `test/models/categorization_run_test.rb`.

Changed: `Gemfile` (+ `anthropic`), `config/deploy.yml` (env.clear), `app/jobs/sync_bank_transactions_job.rb` (enqueue in ensure) and its test, `app/models/bank_transaction.rb` (has_many), `app/services/bank_transactions/categorization.rb` (+ tests), `SKILL.md`, `README.md`, `todo.md`, `CLAUDE.md`.

Owner: `bin/rails credentials:edit` to add `anthropic: api_key:`.

## Order of work

1. **Service, prompt, schema, guardrails, pairing hints, `context(excluding:)`, tests** with the stub client and made-up data. One real request from the development console with seeded categories and a couple of invented rows to confirm the call shape and `parsed_output`.
2. **Persistence, job (per-batch, concurrency limit, cooldown), config, `categorizer_run`/`unsure`/`categorizer_runs` tasks, sync-job enqueue, tests.** Shadow mode default.
3. **Eval task and test.**
4. **Skill, README, todo, CLAUDE.md.**
5. **Rollout (operations):** deploy; `categorizer_eval SAMPLE=200` in production; fix descriptions or prompt until the confident bucket has no wrong decisions on the sample (or the owner accepts the measured rate); shadow runs for a few nights, reading `transactions:unsure`; then `CATEGORIZER_APPLY=1`.

## Verification

- `bin/rails test` green. New tests: prompt assembly (both system blocks, batch TSV, pairing hints incl. a pending other side); parsing and each guardrail; truncation and refusal handling; duplicate and missing ids; job stores decisions, chains batches, respects the cap and the cooldown, applies only confident ones only in apply mode, records errors in ensure; sync job enqueues it even when an account failed; eval excludes sampled rows from precedent and reports both precision buckets; task output shapes. Stub client only, synthetic payees and round amounts.
- Development: one real call end to end against the local database.
- Production: eval output reviewed before apply is enabled; `transactions:categorizer_runs` shows cache reads > 0 from the second batch of a run.

## Cost (Opus 5.5, $4 / $20 per MTok input/output, cache reads $0.20)

| Run | Approx. cost |
|---|---|
| Nightly, ~20 new rows, context ~10k tokens | $0.07 |
| Backlog batch of 50 rows (context cached) | $0.08 |
| Eval of 200 rows | $0.35 |

## Changes during implementation

- Default model is Haiku 4.5 (`claude-haiku-4-5`) at the owner's request; it takes no effort setting, so the request leaves it out for Haiku. The owner asked for "Haiku 5.5", which is not a model ID this codebase knows; `CATEGORIZER_MODEL` switches it.
- No Anthropic API key is available yet: the job skips quietly and the tasks abort with a hint until one is configured. The real-call smoke test is still pending.

## Open points for the owner

- **Model**: Opus 5.5 by default; the eval makes a Sonnet 5.5 comparison a measured, one-line change.
- **Precision bar before enabling apply**: proposed zero wrong confident decisions on a 200-row sample.
- **Cooldown length**: 7 days proposed.
