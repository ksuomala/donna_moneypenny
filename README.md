# Donna Moneypenny

A personal finance app. It fetches your bank transactions through
[Enable Banking](https://enablebanking.com), stores them in the database as events, and shows
you stats.

> I vibe coded this for personal use over one evening. I designed the architecture but did not
> review any of the actual code. I'm already happier with the result than any other similar
> app I've tried before.

## What it does

- **Fetches transactions.** Connect a bank through Enable Banking's open banking API. A daily
  job then pulls new transactions and account balances.
- **Stores them as events.** Every transaction lands in the database as it came from the bank,
  so stats can always be recomputed from the source.
- **Shows stats.** Income and expenses by category, net result, account balances and loan
  balances for any period.

## Categorising transactions

There is no categoriser built in. Use your own LLM.

The app gives it everything it needs through a few rake tasks that print compact,
tab-separated text: the categories with their descriptions, how counterparties were categorised
before, and the oldest uncategorised transactions. The LLM decides, you preview, then write:

```sh
bin/rails transactions:categorization_context
bin/rails transactions:uncategorized LIMIT=200
bin/rails transactions:categorize ASSIGN="101=4,102=4,103=16" DRY_RUN=1
bin/rails transactions:categorize ASSIGN="101=4,102=4,103=16"
```

Writes only ever fill in what is missing, so anything you categorised by hand stays as it is.
A ready-made [Claude Code skill](.claude/skills/categorize-transactions/SKILL.md) runs this
workflow end to end.

## Stack

Rails 8.1 on Ruby 3.4, MySQL, Solid Queue for the daily sync, deployed with Kamal.
