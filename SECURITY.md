# Security & Privacy

Cadence handles your Claude Code credentials and usage data, so it aims to be **radically transparent**. This document explains exactly what the app touches, where data goes, and how you can verify every claim yourself. The entire codebase is ~1,100 lines of Swift — you can audit it in an afternoon.

## TL;DR

- **One** outbound network connection: `https://api.anthropic.com` — Anthropic's own server. Nothing else.
- **No** telemetry, analytics, crash reporting, or third-party services of any kind.
- Your OAuth token is read from the Keychain **at runtime**, kept **in memory**, sent **only to Anthropic**, and is **never logged or written to disk**.
- The only thing Cadence persists is one UI preference (which metric to show in the menu bar).

## What Cadence accesses

### 1. The `ccusage` CLI (local subprocess)

Cadence shells out to the [`ccusage`](https://github.com/ryoppippi/ccusage) command-line tool to read your **local** Claude Code usage logs. It runs two read-only commands every 60 seconds:

```
ccusage blocks --active --json
ccusage daily --json
```

- Arguments are passed as an **array**, never interpolated into a shell string — there is no command-injection surface.
- The one shell invocation is a fixed literal used only to *locate* the binary (`command -v ccusage || command -v npx`); it contains no user or external input.
- See [`Cadence/Services/CCUsageClient.swift`](Cadence/Services/CCUsageClient.swift).

**Supply-chain note:** if you don't have a global `ccusage`, Cadence falls back to `npx --yes ccusage`, which downloads and runs the `ccusage` package from npm. This is the same trust you extend by running `ccusage` yourself. If you prefer to avoid on-the-fly fetches, install it globally first: `npm install -g ccusage`.

### 2. Your Claude Code OAuth token (macOS Keychain)

To show the **real** plan-limit percentages (identical to what `claude`'s `/usage` displays), Cadence reads the OAuth access token that Claude Code already stored in your login Keychain under the item **`Claude Code-credentials`**.

- The first read triggers a standard macOS Keychain permission prompt. Choosing **Always Allow** makes later reads silent. If you **deny** it, Cadence degrades gracefully to time-based estimate bars — no functionality is lost beyond the exact percentages.
- The token is used for exactly one thing: an `Authorization: Bearer` header on a single HTTPS request to `https://api.anthropic.com/api/oauth/usage`.
- The token is **never** written to disk, **never** logged, and **never** sent anywhere except Anthropic.
- See [`Cadence/Services/UsageLimitsService.swift`](Cadence/Services/UsageLimitsService.swift).

### 3. Network

Exactly one endpoint is ever contacted:

```
GET https://api.anthropic.com/api/oauth/usage
```

Always HTTPS. There is no other `URLSession`, socket, or outbound request anywhere in the codebase.

### 4. Local persistence

`UserDefaults` stores a single key — `menuBarMetric` — recording which figure you want in the menu bar. Nothing sensitive is persisted.

## Why Cadence is not sandboxed or notarized

Cadence ships with the App Sandbox and Hardened Runtime **disabled** (`ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = NO`). This is a deliberate, necessary trade-off:

- **Launching subprocesses** (`ccusage` / `npx`) is forbidden inside the App Sandbox.
- **Reading another app's Keychain item** (`Claude Code-credentials`) requires access the sandbox does not grant.

Because Apple **notarization requires the Hardened Runtime**, Cadence is currently distributed as **source you build yourself** (or an ad-hoc-signed CI build), not as a notarized DMG. Building from source means the binary you run is the code you just read.

## Verify it yourself

Don't take our word for it. From a clone of the repo:

```bash
# Every network endpoint the app can reach:
grep -rn "http" Cadence --include='*.swift'

# Every subprocess / shell invocation:
grep -rniE 'Process\(|executableURL|/bin/|npx|launchPath' Cadence --include='*.swift'

# Confirm the token is never logged or written to disk:
grep -rniE 'print\(|NSLog|os_log|FileManager|write\(' Cadence --include='*.swift'
```

At runtime, point a network monitor (Little Snitch, LuLu, or `Console.app`) at Cadence and confirm the only host it talks to is `api.anthropic.com`.

## Reporting a vulnerability

If you find a security issue, **please do not open a public issue.** Instead:

- Use GitHub's **[private vulnerability reporting](https://github.com/MatiasPC/Cadence/security/advisories/new)** (Security → Report a vulnerability), or
- Email the maintainer directly.

We'll acknowledge within a few days and credit you (if you'd like) once a fix ships.

## Supported versions

Cadence is a small, actively developed hobby project. Security fixes land on `main` and in the latest release. Please run the newest version before reporting.
