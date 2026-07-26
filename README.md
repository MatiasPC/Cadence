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
<em>📸 Screenshot coming soon — drop a PNG here and reference it.</em>
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

### Option A — Build from source (recommended)

```bash
# 1. Clone
git clone https://github.com/MatiasPC/Cadence.git
cd Cadence

# 2. Open in Xcode (the .xcodeproj is committed — no extra tooling needed)
open Cadence.xcodeproj

# 3. Select the "Cadence" scheme and press ⌘R.
```

The `DesignSystem` UI package is resolved automatically from GitHub on first build — nothing to install.

Prefer the command line?

```bash
xcodebuild -project Cadence.xcodeproj -scheme Cadence -configuration Release build
```

### Option B — Download a build

Grab the latest `.app` from the [**Releases**](https://github.com/MatiasPC/Cadence/releases) page (built by CI).

> [!IMPORTANT]
> Because Cadence needs to launch subprocesses and read your Keychain, it is **not** sandboxed and is **not** notarized. macOS Gatekeeper will warn on first launch. To open it: **right-click the app → Open → Open**, or run `xattr -dr com.apple.quarantine /path/to/Cadence.app`. Building from source (Option A) avoids this entirely.

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
