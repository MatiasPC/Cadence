<div align="center">

# Cadence

**A minimal macOS menu-bar monitor for your Claude Code usage.**

Live spend, burn rate, model split, and real plan-limit bars — always one glance away.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-26%2B-black.svg?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg?logo=swift)](https://swift.org)
[![Build](https://github.com/MatiasPC/Cadence/actions/workflows/build.yml/badge.svg)](https://github.com/MatiasPC/Cadence/actions/workflows/build.yml)

</div>

---

> [!NOTE]
> Cadence is an **unofficial, community-built** tool. It is not affiliated with, endorsed by, or supported by Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic.

## What it is

Cadence lives in your menu bar and shows — at a glance — how much of your Claude Code usage you've burned through. Click it for a compact Liquid Glass panel with the full picture:

- **Menu-bar label** — pick what it shows: session %, weekly %, or session cost.
- **Active 5-hour block** — live cost, tokens, burn rate ($/hr), and a projected total.
- **Real plan-limit bars** — the *same* numbers Claude Code's `/usage` shows (5-hour, 7-day, and 7-day Opus windows), when available. Falls back to time-based estimates otherwise.
- **Today & this week** — spend and token totals, plus an Opus / Sonnet / Haiku model split.
- **All-time cost** — your cumulative Claude Code spend.

It refreshes automatically every 60 seconds.

<div align="center">
<br>
<em> <img width="300" height="320" alt="image" src="https://github.com/user-attachments/assets/df0b99a7-1f09-43f6-97b9-c997516398dc" />
</em>
<br><br>
</div>

## Requirements

| Requirement | Why |
|---|---|
| **macOS 26 (Tahoe) or later** | Uses Liquid Glass UI APIs. |
| **[ccusage](https://github.com/ryoppippi/ccusage)** | Cadence reads your local Claude Code usage through it. Install with `npm install -g ccusage`, or let Cadence fall back to `npx --yes ccusage` (no install, slower first run). |
| **Node.js 18+** | Needed to run `ccusage` / `npx`. |
| **Xcode 26+** | Only if you build from source. |

## Quick start

First, install the `ccusage` CLI that Cadence reads your usage from (all options need this):

```bash
npm install -g ccusage
```

### Option A — Homebrew 👈 easiest

```bash
brew tap matiaspc/tap
brew trust --cask matiaspc/tap/cadence   # one-time; Homebrew 6+ requires this for third-party taps
brew install --cask matiaspc/tap/cadence
```

Then launch **Cadence** — it lives in your **menu bar** (no Dock icon). The cask automatically clears the macOS quarantine flag, so it opens without a Gatekeeper block. Upgrade later with `brew upgrade --cask matiaspc/tap/cadence`.

### Option B — Download the app (no Homebrew)

1. Download **`Cadence.zip`** from the [**latest release**](https://github.com/MatiasPC/Cadence/releases/latest) and unzip it.
2. Move **Cadence.app** to your `/Applications` folder.
3. **One-time unlock** — the app isn't notarized by Apple, so macOS blocks it until you clear the "downloaded from the internet" flag. In **Terminal**, run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Cadence.app
   ```
4. Double-click **Cadence**. It lives in your **menu bar** (no Dock icon).

> [!NOTE]
> The unlock step exists because notarization requires a paid Apple Developer account this build doesn't use. Cadence is un-sandboxed on purpose — it launches `ccusage` and reads your Keychain. Homebrew (Option A) and building from source (Option C) both avoid the manual step.

### Option C — Build from source

```bash
git clone https://github.com/MatiasPC/Cadence.git
cd Cadence
open Cadence.xcodeproj      # the .xcodeproj is committed — no extra tooling needed
# Select the "Cadence" scheme and press ⌘R.
```

The `DesignSystem` UI package resolves automatically from GitHub on first build — nothing to install. Prefer the command line? `xcodebuild -project Cadence.xcodeproj -scheme Cadence -configuration Release build`

### First run

On first launch Cadence asks macOS for permission to read the `Claude Code-credentials` Keychain item (that's what powers the *real* limit bars — see [Privacy & Security](#privacy--security)). Choose **Always Allow** for silent refreshes. If you decline, everything still works — Cadence just shows time-based estimate bars instead.

## How it works

```
┌─────────────┐   subprocess    ┌──────────┐   reads    ┌────────────────────┐
│  Cadence    │ ──────────────▶ │ ccusage  │ ─────────▶ │ ~/.claude logs     │
│ (menu bar)  │   blocks/daily  │  (CLI)   │            │ (local, on-device) │
└──────┬──────┘                 └──────────┘            └────────────────────┘
       │
       │  HTTPS GET (Bearer token from your Keychain)
       ▼
  api.anthropic.com/api/oauth/usage   ← real plan-limit %, same as /usage
```

- Usage numbers come from the local **`ccusage`** CLI (two commands run concurrently, off the main thread).
- The optional **real plan-limit bars** come from one HTTPS call to Anthropic's own usage endpoint, authenticated with the OAuth token Claude Code already stored in your Keychain. **That token stays on your machine and is only ever sent to Anthropic.** Full details in [SECURITY.md](SECURITY.md).

## Privacy & Security

Cadence is designed to be boringly trustworthy, and the code is short enough to read in one sitting:

- **One** network connection, to `api.anthropic.com` only. No telemetry, no analytics, no third-party servers.
- Your Keychain token is read at runtime, held in memory, sent only to Anthropic, and **never logged or written to disk**.
- The only thing persisted locally is a single UI preference.

Read the full, honest breakdown — including how to verify every claim yourself — in **[SECURITY.md](SECURITY.md)**.

## Contributing

Contributions are welcome! See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the dev setup, architecture overview, and coding conventions. Cadence uses the [Velvet UI](https://github.com/MatiasPC/velvet-ui) design system for its interface.

## License

[MIT](LICENSE) © 2026 Matías Peralta Charro
