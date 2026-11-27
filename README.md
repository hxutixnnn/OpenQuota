# OpenQuota

Track your AI coding subscriptions from the macOS menu bar — a personal fork of
[OpenQuota](https://github.com/robinebers/openusage), pinned to **v0.7.16**.

OpenQuota shows how much of each AI plan you've used — session and weekly limits,
credits, spend — in one popover, and pins the numbers you care about into the menu
bar. It is the v0.7.16 app plus a small set of patches that make the readings match
reality.

- macOS 15 (Sequoia) or later, universal binary
- Swift 6, MIT
- Site: [openquota.hxutixnnn.dev](https://openquota.hxutixnnn.dev)

## What this fork changes

| Patch | Why |
| --- | --- |
| **Antigravity quota truth** | Google's two quota servers disagree — `cloudcode-pa` has reported every bucket at 100% left while `daily-cloudcode-pa` carried the real usage. OpenQuota asks both and keeps the most-consumed bucket, so a spent week reads as spent. |
| **Antigravity Prompt / Flow credits** | The plan's own credit balances (`availablePromptCredits` / `availableFlowCredits`) become two percent meters, read from the local Antigravity agent. The quota buckets alone can read 100% while these are nearly gone. |
| **Abacus.AI provider** | New provider that reads the usage your `abacusai` CLI already tracks (one `get_usage` request, no turn, no credits), instead of the per-user endpoint that returns null pools for enterprise orgs. The monthly row counts down to the 1st. |
| **Devin Daily / Weekly pinned** | Both quota meters are in the menu bar on a fresh install instead of hiding in the popover. |
| **Mistral provider** | Monthly API and Vibe & Studio allowances as percent meters, with pacing: the row projects where the month lands at reset and warns when the burn rate would exhaust it early. |
| **openquota CLI** | The command-line helper installs as `openquota`, and installing it removes a stale pre-rebrand `openusage` link. |

Everything else — providers, layout, CLI, local API — is upstream v0.7.16 behaviour.

## Install

**Download:** grab `OpenQuota-0.7.17.zip` from the
[latest release](https://github.com/hxutixnnn/OpenQuota/releases/latest), unzip it and drag
`OpenQuota.app` to Applications. It is ad-hoc signed, not notarized: on first launch,
right-click the app and choose **Open**.

**From source:** requires macOS 15+ and the Xcode command line tools.

```sh
git clone https://github.com/hxutixnnn/OpenQuota.git
cd OpenQuota

# build and stage a signed-for-local-use app in dist/ (about 2 minutes)
BUNDLE_ID=com.hxutixnnn.openquota ./script/build_and_run.sh build

# install it (the build stages OpenQuota.app)
cp -R dist/OpenQuota.app /Applications/
```

The build is ad-hoc signed, which has two consequences: iCloud sync stays off, and
in-app updates are disabled (there is no Sparkle feed). `brew upgrade --cask
openusage` installs upstream over it.

The default bundle id is `com.hxutixnnn.openquota`. Passing
`BUNDLE_ID=com.robinebers.openusage` inherits an existing OpenUsage install's settings,
pins and sign-ins instead of starting fresh.

## Supported providers

- **[Antigravity](docs/providers/antigravity.md)** — shared Gemini and Claude pool quotas, 5-hour and weekly windows, plus Prompt/Flow credits
- **[Abacus.AI](Sources/OpenUsage/Providers/AbacusAI)** — monthly account credits from the `abacusai` CLI
- **[Claude](docs/providers/claude.md)** — session, weekly, model-specific limits, extra usage, local daily spend
- **[Codex](docs/providers/codex.md)** — session, weekly, credits, local daily spend
- **[Copilot](docs/providers/copilot.md)** — AI credits, extra usage, organization billing, chat and completions
- **[Cursor](docs/providers/cursor.md)** — credits, total usage, Grok Bot, Cursor Models, Other Models, requests, on-demand, per-day spend
- **[Devin](docs/providers/devin.md)** — weekly and daily quota, extra usage balance
- **[Grok](docs/providers/grok.md)** — weekly shared pool, pay-as-you-go, local daily spend
- **[Mistral](docs/providers/mistral.md)** — monthly API/Studio and Vibe & Studio allowance meters, pay-as-you-go flag (API key)
- **[Ollama](docs/providers/ollama.md)** — Ollama Cloud monthly credits (or session and weekly limits on legacy plans), purchased credits
- **[OpenCode](docs/providers/opencode.md)** — Go session/weekly/monthly caps, Zen spend, local daily spend
- **[OpenRouter](docs/providers/openrouter.md)** — credit balance, daily/weekly/monthly spend (API key)
- **[Z.ai](docs/providers/zai.md)** — session, weekly, web-search quotas (GLM Coding Plan, API key)

Most providers reuse the credentials already on your machine (keychain, auth files,
app state) — no extra login. Mistral, OpenRouter and Z.ai are the exceptions and need
an API key. Credentials are used only for that provider's requests.

## Using it

- **Menu bar pins** — up to 2 metrics per provider, as compact text or mini bars.
- **Dashboard popover** — grouped meters with reset countdowns and pace; right-click a row to hide, star, refresh, or open Customize.
- **Global shortcut** — toggle the popover from anywhere.
- **Stale-while-revalidate** — cached values at launch, refresh every 5 minutes.
- **One-shot CLI** — `openquota [provider] [--force]` prints stable JSON limits without the app running ([docs](docs/cli.md)).
- **Local API** — `127.0.0.1:6736/v1/limits`, loopback only ([docs](docs/local-http-api.md)).

## Development

```sh
swift build                 # debug build
swift test                  # test suite
./script/build_and_run.sh   # build and launch the dev app from dist/
```

Architecture: one SwiftPM module shared by the app and the CLI; providers implement
`ProviderRuntime` (auth store → usage client → mapper → `ProviderSnapshot`). See
[docs/architecture.md](docs/architecture.md) and [docs/adding-a-provider.md](docs/adding-a-provider.md).

## Upstream and license

This is an unaffiliated personal fork of
[robinebers/openusage](https://github.com/robinebers/openusage), pinned at tag
`v0.7.16`. Upstream remains the supported app; bug reports about the patches belong
here, everything else belongs upstream.

Code is [MIT](LICENSE). The OpenQuota name and logo are upstream's and are not used
as this fork's identity.
