---
name: categorize-transactions
description: Categorize uncategorized BankTransactions in the donna_moneypenny production database, following the category descriptions. Use when asked to categorize transactions, work through the uncategorized backlog, or check how transactions are categorized.
---

# Categorize bank transactions

Assign a `TransactionCategory` to each uncategorized booked `BankTransaction`, so the app's
reports are right. Precision matters more than coverage: a transaction left uncategorized is
harmless, one in the wrong category silently skews every report.

Rules come first: references, reference prefixes and the same amount to the same counterparty
(`CategorizationRule`), created from the history when they have been used consistently at least
three times, and switched off automatically as soon as a categorization contradicts them. Then the
app categorizes the rest by itself every night after the sync (`CategorizeTransactionsJob`, with
a model through the API: OpenAI's GPT-6 Luna by default, `CATEGORIZER_MODEL` in
`config/deploy.yml` picks another, Claude `claude-*` or TypeSafe `jev-*`). Every decision is
stored. In production `CATEGORIZER_APPLY` is on, so the confident decisions are written to the
transactions and the unsure ones are kept with a best guess; without it the job only stores
decisions (shadow mode). This skill handles what the categorizer was unsure about, and keeps the
rules it follows (the category descriptions) up to date.

Everything is per user. Each user has their own categories, rules, loans and accounts, and the
nightly rules pass and categorizer run once for every user who has categories, each run built
from that user's data alone: nothing of one user's reaches another's model context, and a
transfer between two users' accounts is not an own transfer for either.

## Commands

All database access goes through `BankTransactions::Categorization`
(`app/services/bank_transactions/categorization.rb`) via rake tasks. Never write to the
database any other way (no `rails runner` updates, no console). Production is reached through
Kamal. Drop the `bin/kamal app exec --reuse '…'` wrapper to run against the local database.

```sh
# Read-only: the user's latest categorizer run's unsure decisions, grouped by counterparty, with
# the model's guess, reason, and the guardrail that stopped it. The skill starts here.
bin/kamal app exec --reuse 'bin/rails transactions:unsure'
# Read-only: every user's categorizer runs with counts, tokens and cost
bin/kamal app exec --reuse 'bin/rails transactions:categorizer_runs'
# Run the categorizer now instead of waiting for the nightly sync: the user's backlog in the
# background, ALL=1 for every user, DRY_RUN=1 for one batch printed and nothing stored
bin/kamal app exec --reuse 'bin/rails transactions:categorizer_run'
bin/kamal app exec --reuse 'bin/rails transactions:categorizer_run DRY_RUN=1 LIMIT=20'
# Test the categorizer on the user's already categorized transactions (writes nothing; costs API
# tokens). Run it after changing descriptions, before trusting the change.
bin/kamal app exec --reuse 'bin/rails transactions:categorizer_eval SAMPLE=200'

# Rules: every rule with its matches and conflicts; a manual rule (e.g. a loan's installment
# reference prefix); switch one off or on
bin/kamal app exec --reuse 'bin/rails rules:list'
bin/kamal app exec --reuse 'bin/rails rules:upsert CATEGORY="Loans" LOAN="Mortgage" PREFIX="12345678"'
bin/kamal app exec --reuse 'bin/rails rules:toggle ID=3'

# Read-only: categories with their descriptions, accounts, and earlier decisions per counterparty
bin/kamal app exec --reuse 'bin/rails transactions:categorization_context'

# Read-only: the oldest uncategorized booked transactions
bin/kamal app exec --reuse 'bin/rails transactions:uncategorized LIMIT=200'

# Preview, then write. Pairs are transaction_id=category_id
bin/kamal app exec --reuse 'bin/rails transactions:categorize ASSIGN="101=4,102=4,103=16" DRY_RUN=1'
bin/kamal app exec --reuse 'bin/rails transactions:categorize ASSIGN="101=4,102=4,103=16"'

# Read-only: Loans-category transactions without a loan, and how earlier ones were linked
# (interest and fees on a credit card are left out: they belong to the card, not to a loan)
bin/kamal app exec --reuse 'bin/rails transactions:unlinked_loans'

# Preview, then link. Pairs are transaction_id=loan_id
bin/kamal app exec --reuse 'bin/rails transactions:link_loans ASSIGN="201=1,202=6" DRY_RUN=1'
bin/kamal app exec --reuse 'bin/rails transactions:link_loans ASSIGN="201=1,202=6"'
```

```sh
# Fetch today's transactions and balances now instead of waiting for the 19:00 sync, e.g. when
# a card payment's other side is still pending. Then: read-only list of every account's balance.
bin/kamal app exec --reuse 'bin/rails bank:sync'
bin/kamal app exec --reuse 'bin/rails accounts:balances'
```

Every task above works on the owner's data. For another user, add `EMAIL=their@address` to the
command: every `transactions:*`, `rules:*` and `categories:*` task then acts for that user, on
their transactions, categories, rules, loans and runs. `bank:sync` and `accounts:balances` cover
every connection regardless.

`categorize` and `link_loans` only fill in what's missing. It skips transactions that already have one
(including ones the user set by hand) and pending ones (the sync replaces those every day).
It refuses unknown categories and categories that have sub-categories.

## Workflow

0. **Start from the categorizer.** `transactions:unsure` lists what the nightly run could
   not decide, with its guess. Work through those first with the steps below; for a large
   backlog when the categorizer is off, fall back to `transactions:uncategorized`.
1. **Load the context** and read every category description. The descriptions are the rules.
   The "known counterparties" list shows earlier decisions; follow them unless they clearly
   contradict a description.
2. **Fetch a batch** of uncategorized transactions (up to 200 at a time).
3. **Decide each transaction**, using the signals below. Sort them into:
   - *confident*: the description and the data agree
   - *unsure*: anything else, which stays uncategorized
4. **Preview** the confident assignments with `DRY_RUN=1` and check that the per-category counts
   look plausible.
5. **Write** them. Batches of at most ~100 pairs keep the command readable.
6. **Repeat** from step 2 until the backlog is empty or only unsure ones are left.
7. **Link loan transactions.** Every transaction in Loans belongs to one of the loans in the
   context (matched by counterparty, reference and account, as described on the loan). Link
   them with `link_loans`. A loan payment that matches no loan is a question for the user:
   it may be a new loan. Never record loan balances yourself; the user enters those from
   their loan statements (`loans:record_balance`).
8. **Report** to the user: how many were categorized per category, and the unsure ones as a
   short table (date, amount, counterparty, description, your best guess) with a concrete
   question for each group. Ask about groups (e.g. "the 9 payments from the same counterparty"), not
   single rows.

## Signals and rules

The signals (strongest first) and the rules that are easy to get wrong are kept in one place,
shared with the nightly categorizer: `app/services/bank_transactions/categorizer/prompt.md`.
Read it before deciding anything, and follow it the same way the categorizer does. Change it
there, never here, so the two never drift apart; then run `transactions:categorizer_eval`.

**Never re-categorize on your own.** If an existing category looks wrong, report it to the user
instead of changing it. When the user decides a move, `transactions:recategorize ASSIGN=...`
(same pairs as `categorize`, `DRY_RUN=1` first) moves transactions whatever their category and
drops a loan link.

## When you learn something

When the user answers a question with a rule that will come up again (which tenant rents which
apartment, which reference belongs to which loan), it goes into the category's description, not
just into this run. Propose the new text and, once the user agrees, write it:

```sh
bin/kamal app exec --reuse 'bin/rails categories:list'                       # current descriptions
bin/kamal app exec --reuse 'bin/rails categories:upsert NAME="Loans" DESCRIPTION="…"'
```

The descriptions in the database are the shared source of truth, also for the nightly
categorizer. A changed description makes the categorizer reconsider the transactions it was
unsure about on its next run. Each user's descriptions are their own: a rule learned for one
user goes into that user's category (`EMAIL=...`), not the owner's. `db/seeds.rb` only holds
generic defaults and never overwrites them.
