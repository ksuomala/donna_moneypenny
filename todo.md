# To-do

Goal: read Nordea transactions through Enable Banking and store them in the database.
Server and infrastructure tasks live in the devops repo (`~/code_ksuomala/devops`, `docs/open-issues.md`).

## Enable Banking: setup (done)

- [x] Enable Banking client that signs RS256 JWTs (`app/services/enable_banking/client.rb`)
- [x] Public `/privacy` and `/terms` pages (required by the application registration)
- [x] Production application registered in the Enable Banking Control Panel
      (redirect URL `https://donamoneypenny.app/enable_banking/sessions`; the app ID is in the encrypted credentials)
- [x] Activated in restricted mode by linking own Nordea accounts in the Control Panel
- [x] Application ID and private key stored in Rails encrypted credentials (`enable_banking:`)

## Nordea login from the app

- [x] HTTP basic auth on everything except `/up`, `/privacy`, `/terms` (login in credentials: `basic_auth:`)
- [x] "Connect Nordea" button: `POST /auth` with a random `state` and the longest consent Nordea allows (180 days)
- [x] Callback checks `state`, exchanges the code for a session, stores `BankConnection` + `BankAccount`s
- [x] Tests for the login flow and the client
- [x] Deploy and do the first real Nordea login from https://donamoneypenny.app (2026-10-11)
- [x] Account names from `product` (Nordea puts the holder in `name`); accounts matched by `identification_hash` on reconnect (the credit card has no IBAN)

## Import transactions

What the real data looks like (2026-10-11): current accounts plus a credit card.
Transactions carry `entry_reference` but **no `transaction_id`**, plus `booking_date`, `value_date`,
`transaction_date`, `transaction_amount`, `credit_debit_indicator`, `creditor`/`debtor`,
`remittance_information`, `reference_number`, `merchant_category_code`, `balance_after_transaction`,
`status` (`BOOK` / `PDNG`). The credit card paginates (`continuation_key`) even for 30 days and has
many pending rows. Still to check: whether pending rows have an `entry_reference`, and whether it
stays the same once they're booked.

- [x] `BankTransaction` model: account, `entry_reference` (unique per account),
      booking and value date, signed amount, currency, counterparty, message, reference number,
      booked/pending status, raw JSON
- [x] Sync service (`BankTransactions::Sync`): first sync looks back 1 year, later syncs re-fetch 14 days before the newest booked row; follows `continuation_key`; upserts
- [x] Pending transactions are replaced as a set on every sync, so booked versions and cancelled holds leave no duplicates
- [x] Daily `SyncBankTransactionsJob` at 19:00 Europe/Helsinki (`config/recurring.yml`, production)
- [x] First sync run by hand on 2026-10-11
- [ ] "Sync now" button (signal that the user is present, so it doesn't count toward the bank's ~4 unattended fetches a day)
- [ ] Notice when the daily sync fails (currently only visible in logs and Solid Queue's failed jobs)
- [ ] Transactions page (list, filter by account and month)
- [x] Tests for paging, deduplication, pending → booked, the job and its schedule

## Categorize transactions

- [x] `TransactionCategory` with kind (expense / income / transfer / investment), description and one level of
      sub-categories; transactions go on leaf categories only. Generic defaults in `db/seeds.rb`, own categories via `categories:import`
- [x] Categorize transactions automatically (Claude), using the category descriptions as instructions
      (`CategorizeTransactionsJob` after the sync, shadow mode by default, `transactions:categorizer_eval`)
- [ ] Add the Anthropic API key to the credentials, run the eval in production, then set `CATEGORIZER_APPLY: "true"`

## Stats

- [x] Stats page (`/stats`): income and expense totals per category for this week / month / year or a custom range,
      as bar and pie charts. Each investment sub-category is netted into one figure (income if positive, expense if negative)
- [ ] Check whether Nordea posts credit card interest as its own line (Loans) or inside the invoice payment

## Consent and reliability

- [ ] Mark connections as expired when the consent runs out, and show a "Reconnect" prompt
- [ ] Sync flags expired or revoked sessions instead of failing silently
- [ ] Revisit backups before real bank data accumulates (deferred, see devops repo `docs/backups.md`)

## Later

- [ ] Map bank transactions to `Expense` / `Income` categories (rules by counterparty or message)
- [ ] Replace basic auth with proper login (`bin/rails generate authentication`) if more than one device or user needs it
- [ ] Add a contact email to `/privacy` and `/terms`

## Credit cards and balances (issue #5)

- [x] `CreditCard` account type (single-table inheritance), set from the bank's `cash_account_type` CARD; existing card backfilled
- [x] Daily sync also fetches `GET /accounts/{uid}/balances` and keeps one `BankAccountBalance` snapshot per account per day (booked, available, raw)
- [x] Stats page: accounts section with balances, credit cards in the loans table (owed, change, purchases as taken, payments as paid, credit limit)
- [x] `transactions:unlinked_loans` skips credit cards; `bank:sync` and `accounts:balances` rake tasks
- [ ] Loans at other banks: check whether they're reachable through Enable Banking; until then they stay loans with statement balances
