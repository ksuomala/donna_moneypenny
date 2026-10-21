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

## Automatic categorisation

After every nightly sync, rules go first. A rule matches a reference, a reference prefix, or the
same amount to the same counterparty; rules are derived from your own history once a pattern
has held at least three times, and switch themselves off when you categorise a matching
transaction differently (`bin/rails rules:list`, `rules:upsert`, `rules:toggle`).

Then a background job sends the remaining uncategorised transactions to a model
(OpenAI GPT-6 Luna by default; `CATEGORIZER_MODEL` picks OpenAI `gpt-*`, Claude `claude-*` or TypeSafe `jev-*`) in batches, with the category
descriptions, the earlier decisions and every field of each transaction, and gets back a
decision per transaction in a fixed JSON schema. Code guardrails then turn risky answers into
unsure ones. Every decision is stored with its reason. Confident ones are written only once
`CATEGORIZER_APPLY` is `true`; until then the job runs in shadow mode.

```sh
bin/rails credentials:edit                         # add anthropic: api_key: ...
bin/rails transactions:categorizer_eval SAMPLE=200 # precision on transactions you already categorised
bin/rails transactions:categorizer_run DRY_RUN=1   # one batch, printed, nothing stored
bin/rails transactions:unsure                      # what the latest run wasn't sure about
bin/rails transactions:categorizer_runs            # runs, tokens and cost
```

Without an API key the job does nothing.

## Users

Every page needs a sign-in (Rails' built-in authentication). There is no sign-up page and no
password reset by email; users are created and their passwords changed from the command line:

```sh
bin/rails users:create EMAIL=you@example.com   # asks for the password (12+ characters)
bin/rails users:password EMAIL=you@example.com # also signs out its sessions
```

Each user has their own bank connections, categories, rules and loans. The first user created
also gets every record that has no owner yet. The nightly sync, the categorizer and the rake
tasks still work on the first user's data.

## Stack

Rails 8.1 on Ruby 3.4, MySQL, Solid Queue for the daily sync, deployed with Kamal.
