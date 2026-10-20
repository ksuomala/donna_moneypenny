# Donna Moneypenny

Personal finance app: Rails 8.1, MySQL, Solid Queue, deployed with Kamal. See `README.md` for
what it does and `.claude/skills/categorize-transactions/SKILL.md` for the categorization
workflow and the rake tasks.

## Personal data never goes into git

This repo is public-shaped: it holds the app, generic defaults and made-up examples. The
owner's real data lives in the production database and in a private repo outside this one.

- Never put anything read from the production database into code, tests, fixtures, seeds,
  docs, skills, comments or commit messages: counterparty and tenant names, reference
  numbers, IBANs, account names, addresses, amounts, category names that describe the
  owner's holdings.
- The categorizer prompt (`app/services/bank_transactions/categorizer/prompt.md`) is generic:
  owner-specific rules go into the category descriptions in the database, never into it. The
  same goes for eval output: read it, don't commit or paste it into PRs.
- Tests and examples use invented names (`K-Market`, `Housing Oy`, `Apartment A`, reference
  `12345`). If an example needs to look real, make it up.
- Reading production data to answer a question or to run a task is fine, and deploying code
  that then runs on the owner's data is the point. Committing that data is not.
- Owner-specific configuration (the category descriptions) is applied to the database from
  the private repo, never checked in here. `db/seeds.rb` holds generic defaults only.

## Database writes

All writes to transactions and categories go through the rake tasks in `lib/tasks/`, which
fill in what is missing and never overwrite the owner's decisions. No ad-hoc `rails runner`
or console updates against the production database.
