# Mistral

Tracks your Mistral monthly allowances using an API key you supply — Mistral has no companion app or
CLI that stashes a login, so there is nothing local to read on its own.

## What it tracks

| Metric | Meaning |
|---|---|
| API Allowance | Share of this month's API/Studio allowance used (€ allowance, shown as %) |
| Vibe & Studio Allowance | Share of this month's Vibe & Studio allowance used (€ allowance, shown as %) |
| Pay-as-you-go | Whether either allowance can continue past its cap with pay-as-you-go billing |

Both allowances reset on the first day of each calendar month; the meters show the reset date. Mistral
bills in EUR and reports each allowance as a percentage of its monthly cap, so the meters show that
percentage rather than a dollar figure — OpenQuota's currency format is USD-only. Because the cap is
large (€25.50 of API and €255 of Vibe & Studio on the Individual plan), a normal day's usage is a
fraction of a percent: the meters keep one decimal below 10% and two below 1%, so the reading still
moves instead of sitting on 0%. When Mistral reports your plan name, OpenQuota shows it beside the
provider name.

Because the monthly window is known, both allowances also pace: the row projects where this month's
spend lands at reset, turns amber or red with a run-out time when the burn rate would exhaust the
allowance before it refills, and gains the steady-use tick with **Always Show Pacing** on. Rows below
5% used keep the plain blue reading rather than project a whole month from a fraction of a percent.
Pacing stops while `reset_at` is missing, since there is no window to project across.

## Where credentials come from

Add your Mistral API key in **Customize → Mistral → API Key**, set `MISTRAL_API_KEY`, or write
`~/.config/openquota/mistral.json` (`{"apiKey":"…"}`). A saved key wins over an environment variable.
Create a key under **API Keys** at [admin.mistral.ai](https://admin.mistral.ai).

The budget read requires the organization inference-usage permission (`see_org_inference_usage`); a
key without it returns 403 and the card reports the key as invalid.

## Under the hood

Two calls under `https://api.mistral.ai/v1` with `Authorization: Bearer <key>`:

- `GET /billing/budget` → `api_budget` and `vibe_budget`, each `usage_percentage`, `initial_budget`
  (EUR), `reset_at`, `payg_enabled`. `reset_at` drives both the countdown and the pacing window, which
  starts one calendar month earlier.
- `GET /billing/subscription` → `plan_name` and per-service pay-as-you-go flags

The meters come entirely from `/billing/budget`; the subscription call only supplies the plan badge,
so its failure degrades quietly while a budget failure is the real error.

## Troubleshooting

- **"No Mistral API key"** — add the key in Customize or export `MISTRAL_API_KEY`, then refresh.
- **"Mistral API key invalid"** — the key was rejected or lacks the org-usage permission; mint a fresh
  key at admin.mistral.ai.
