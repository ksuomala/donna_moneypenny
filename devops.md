# DevOps notes — donna_moneypenny (2026-10-06)

## 1. Stack

Fresh Rails 8.1.4 / Ruby 3.4.7 app. Switched from the SQLite default to **MySQL 8.0** early
on (accessory container via Kamal) for production parity with a more traditional setup.
Models: `Expense` and `Income`, both with category/payment-method enums and basic validations.

An EnableBanking (open banking) integration was also started: `EnableBanking::Client`
(`app/services/enable_banking/client.rb`) signs its own JWTs (RS256, keyed by application ID)
to call the Enable Banking API, and `EnableBanking::SessionsController#create`
(`app/controllers/enable_banking/`) is the registered redirect/callback endpoint
(`GET /enable_banking/sessions`) that exchanges an authorization code for a session. This is
implemented and smoke-tested against the real Enable Banking API (confirmed a correctly
signed JWT gets a legitimate 403 back for a non-existent test application ID) but **not yet
wired up with a real registered Enable Banking application** — `ENABLE_BANKING_APPLICATION_ID`
/ `ENABLE_BANKING_PRIVATE_KEY` are read from `ENV` with no production values set yet.

## 2. Domain

The production domain is **`donamoneypenny.app`** — note the spelling: it's missing the
second "n" from "donna". This was a typo made at registration time (via Cloudflare Registrar),
and Cloudflare's domain registrations are non-refundable (confirmed via their own ToS and
support threads), so the typo'd domain is what's actually in use. `donnamoneypenny.app` (the
correct spelling) was never registered.

DNS is on Cloudflare. Both the apex and `www` have their own Let's Encrypt certs (see
`proxy.hosts` in `config/deploy.yml` — note the plural `hosts` key, not `host`; passing an
array to the singular `host` key raises `Kamal::ConfigurationError`).

## 3. Server, infrastructure and secrets

Everything shared across the apps on the Hetzner box (server, kamal-proxy, DNS, secrets
inventory, backups, runbooks, migration history) is documented in the **devops repo** at
`~/code_ksuomala/devops`. Start with its `README.md`; this app's page there is
`docs/apps/donna_moneypenny.md`.

## 4. What's still open (app-specific)

- EnableBanking isn't fully wired up yet. It needs a real registered application
  (`ENABLE_BANKING_APPLICATION_ID` / `ENABLE_BANKING_PRIVATE_KEY`) before the callback flow can
  be used for anything real.
- Cross-app and server-level open issues are tracked in the devops repo's `docs/open-issues.md`.
