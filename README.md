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
  balances for any period, in euros or converted to another currency at the ECB rate.
- **Budgets.** A monthly total and per-category amounts from a start date, shown against the
  period's spending on the stats page.
- **Households.** Users in a household can see their stats combined, with payments between
  the members left out.

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
decision per transaction in a fixed JSON schema. Both run once per user: each user's rules,
categories, loans and earlier decisions are their own, and nothing of one user's reaches
another's model context. Code guardrails then turn risky answers into
unsure ones. Every decision is stored with its reason. Confident ones are written only once
`CATEGORIZER_APPLY` is `true`; until then the job runs in shadow mode.

```sh
bin/rails credentials:edit                         # add openai: api_key: ... (or anthropic:, typesafe:)
bin/rails transactions:categorizer_eval SAMPLE=200 # precision on transactions you already categorised
bin/rails transactions:categorizer_run DRY_RUN=1   # one batch, printed, nothing stored
bin/rails transactions:categorizer_run ALL=1       # a run for every user now, as after the sync
bin/rails transactions:unsure                      # what the latest run wasn't sure about
bin/rails transactions:categorizer_runs            # every user's runs, tokens and cost
```

Every task acts for the first user unless `EMAIL=...` names another. Without an API key the job
does nothing.

## Telegram

A bot can send a weekly report on Monday mornings (last week's income, expenses and top
categories, and this month against the budget) and a message when a budget row passes 80 and
100 % of its monthly amount, once per month each, checked after the nightly categorizer. A user
and a household each have a chat of their own; a household without one is reached through its
members' chats. Any bot's token works, also one another program already uses for its own chat:
sending doesn't interfere with receiving.

```sh
bin/rails credentials:edit                                 # add telegram: bot_token: ...
bin/rails telegram:link EMAIL=you@example.com CHAT_ID=123  # your chat with the bot
bin/rails telegram:link HOUSEHOLD=Home CHAT_ID=-456        # a group with the bot in it
bin/rails telegram:test EMAIL=you@example.com
bin/rails telegram:weekly_report DRY_RUN=1                 # print instead of send
bin/rails telegram:budget_alerts DRY_RUN=1
```

`BUDGET_ALERT_THRESHOLDS` (default `80,100`) sets the percentages.

## Users

Every page needs a sign-in (Rails' built-in authentication). There is no sign-up page and no
password reset by email; users are created and their passwords changed from the command line:

```sh
bin/rails users:create EMAIL=you@example.com   # asks for the password (12+ characters)
bin/rails users:password EMAIL=you@example.com # also signs out its sessions
```

Each user has their own bank connections, categories, rules and loans. The first user created
also gets every record that has no owner yet. The nightly sync covers every connection, and the
rules pass and the categorizer run once per user who has categories, each on that user's data
alone. The rake tasks act for the first user unless `EMAIL=...` names another.

## Stack

Rails 8.1 on Ruby 3.4, MySQL, Solid Queue for the daily sync, deployed with Kamal.
