---
name: categorize-transactions
description: Categorize uncategorized BankTransactions in the donna_moneypenny production database, following the category descriptions. Use when asked to categorize transactions, work through the uncategorized backlog, or check how transactions are categorized.
---

# Categorize bank transactions

Assign a `TransactionCategory` to each uncategorized booked `BankTransaction`, so the app's
reports are right. Precision matters more than coverage: a transaction left uncategorized is
harmless, one in the wrong category silently skews every report.

## Commands

All database access goes through `BankTransactions::Categorization`
(`app/services/bank_transactions/categorization.rb`) via rake tasks. Never write to the
database any other way (no `rails runner` updates, no console). Production is reached through
Kamal. Drop the `bin/kamal app exec --reuse '…'` wrapper to run against the local database.

```sh
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

`categorize` and `link_loans` only fill in what's missing. It skips transactions that already have one
(including ones the user set by hand) and pending ones (the sync replaces those every day).
It refuses unknown categories and categories that have sub-categories.

## Workflow

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

## Signals, strongest first

1. **Category descriptions and earlier decisions** for the same counterparty on the same account.
2. **The account.** Some accounts have one purpose (e.g. a rental property's account), so the
   same counterparty can belong to different categories depending on the account.
3. **Reference number.** Recurring payments to the same payee (maintenance fees for different
   apartments, card invoices) are told apart by their reference.
4. **Counterparty name**, including card-payment prefixes (`PTL*`, `SQ*`, `Zettle_*`,
   `Paytrail Oyj <merchant>`, `UBER *TRIP`, `MCD…` = McDonald's).
5. **Merchant category code** (card purchases).
6. **Bank code** (`raw.bank_transaction_code.description`): `Suoritus` = payment received on the
   credit card, `Tilisiirto` = transfer, `Otto` = withdrawal, `Laina Nordea` = loan paid out,
   `Koron pääomitus` = interest credited.
7. **Description** (remittance information).

## Rules that are easy to get wrong

- **Own transfers and credit card payments** are found in pairs: an outgoing payment on one of
  the owner's accounts and an incoming one of the same amount on another (for the card: a payment to the
  card issuer with the card's reference, and a `Suoritus` of the same amount on the card account,
  usually within a few days). Categorize both sides as Own, for the whole amount. Interest and
  fees on the card are not part of the payment: they come as separate rows on the card account
  and go to Loans, with no loan to link (the card is a `CreditCard` account in the app, not a
  loan). A payment with no matching other side is not proven to be Own; treat it as unsure
  unless the description says otherwise. The other side is often still pending; `bank:sync`
  fetches it once the bank has booked it.
- **Transfers between the owner's accounts at the same bank** (bank code `Oma siirto`) are Own.
  Deposits from the owner's accounts at other banks (bank code `Pano`) are not automatically
  Own: follow the Own and Salary descriptions. Transfers with other people, family included,
  are never Own.
- **Refunds** go to the category of the original purchase (a positive amount), not to income.
- **Sub-categories only.** Never assign a category that has sub-categories. Anything spent on
  or received for a specific investment goes to that investment's sub-category, even if it would
  otherwise look like Household, Loans or Hardware store.
- **Large amounts** (over 1 000 € either way) must match a description or an earlier decision
  exactly. Otherwise ask.
- **Never re-categorize.** If an existing category looks wrong, report it to the user instead
  of changing it.

## When you learn something

When the user answers a question with a rule that will come up again (which tenant rents which
apartment, which reference belongs to which loan), it goes into the category's description, not
just into this run. Propose the new text and, once the user agrees, write it:

```sh
bin/kamal app exec --reuse 'bin/rails categories:list'                       # current descriptions
bin/kamal app exec --reuse 'bin/rails categories:upsert NAME="Loans" DESCRIPTION="…"'
```

The descriptions in the database are the shared source of truth, also for automated
categorization later. `db/seeds.rb` only holds generic defaults and never overwrites them.
