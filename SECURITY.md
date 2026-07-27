# Security & Privacy

Cadence handles your Claude Code credentials and usage data, so it aims to be **radically transparent**. This document explains exactly what the app touches, where data goes, and how you can verify every claim yourself. The entire codebase is ~1,700 lines of Swift — you can audit it in an afternoon.

## TL;DR

- **One** outbound network connection: `https://api.anthropic.com` — Anthropic's own server. Nothing else.
- **No** telemetry, analytics, crash reporting, or third-party services of any kind.
- Your OAuth token is read from the Keychain **at runtime**, kept **in memory**, sent **only to Anthropic**, and is **never logged or written to disk**.
- Keychain reads are **silent**. The macOS permission panel only ever appears because you clicked **Allow access** in the panel — never from a background refresh.
- Cadence persists two things, both non-sensitive: one UI preference, and a cache of your own usage numbers so the panel isn't empty at launch. **No credentials are written to disk, ever.**

## What Cadence accesses

### 1. The `ccusage` CLI (local subprocess)

Cadence shells out to the [`ccusage`](https://github.com/ryoppippi/ccusage) command-line tool to read your **local** Claude Code usage logs. It runs two read-only commands on separate cadences — the active block every 60 seconds, the (much more expensive) daily report every 5 minutes:

```
ccusage blocks --active --json          # every 60s
ccusage daily --json --breakdown        # every 5 min
```

- Arguments are passed as an **array**, never interpolated into a shell string — there is no command-injection surface.
- The one shell invocation is a fixed literal used only to *locate* the binary (`command -v ccusage || command -v npx`); it contains no user or external input. It runs as an interactive login shell (`zsh -ilc`) so that it sources your `~/.zshrc` and can therefore see Node version managers (nvm, fnm, volta, asdf) that install outside any system directory. That means Cadence executes your own shell configuration — which is yours, not ours, but it is worth knowing, and it is part of why Cadence cannot be sandboxed.
- If the shell reveals nothing, Cadence falls back to checking a fixed list of known install directories. It never executes anything it finds there beyond `ccusage`/`npx` itself.
- A run that exceeds 30 seconds is killed, so a wedged `node` can't leave the app hanging.
- See [`Cadence/Services/CCUsageClient.swift`](Cadence/Services/CCUsageClient.swift).

**Supply-chain note:** if you don't have a global `ccusage`, Cadence falls back to `npx --yes ccusage`, which downloads and runs the `ccusage` package from npm. This is the same trust you extend by running `ccusage` yourself. If you prefer to avoid on-the-fly fetches, install it globally first: `npm install -g ccusage`.

### 2. Your Claude Code OAuth token (macOS Keychain)

To show the **real** plan-limit percentages (identical to what `claude`'s `/usage` displays), Cadence reads the OAuth access token that Claude Code already stored in your login Keychain under the item **`Claude Code-credentials`**.

- **Reads are silent by default.** Cadence suppresses Keychain user interaction on every background read, so a polling refresh can never raise a system dialog. If the ACL doesn't grant access, the read simply fails and the panel shows a row offering to ask.
- **The permission panel is only ever triggered by you.** It appears solely when you press **Allow access** in the panel — a direct response to a click, never an interruption.
- If you never grant it (or you deny it), Cadence degrades gracefully to time-based estimate bars. Nothing is lost beyond the exact percentages.
- After a successful read the token is held **in memory only**, so routine polling doesn't touch the Keychain again. It is re-read only if the API rejects it — Claude Code rotates this token, and a rotation must not spawn a dialog either, so that re-read is silent too.
- The token is used for exactly one thing: an `Authorization: Bearer` header on a single HTTPS request to `https://api.anthropic.com/api/oauth/usage`.
- The token is **never** written to disk, **never** logged, and **never** sent anywhere except Anthropic.
- See [`Cadence/Services/ClaudeCredentials.swift`](Cadence/Services/ClaudeCredentials.swift) (the Keychain read) and [`Cadence/Services/UsageLimitsService.swift`](Cadence/Services/UsageLimitsService.swift) (the request).

### 3. Network

Exactly one endpoint is ever contacted:

```
GET https://api.anthropic.com/api/oauth/usage
```

Always HTTPS. There is no other `URLSession`, socket, or outbound request anywhere in the codebase.

### 4. Local persistence

Cadence writes exactly two things, neither of them a credential:

| What | Where | Why |
|---|---|---|
| `menuBarMetric` | `UserDefaults` | Which figure you want in the menu bar. |
| `usage-cache.json` | `~/Library/Application Support/Cadence/` | The last successful snapshot — your own cost and token numbers, plus the limit percentages — so a relaunch shows real values instead of an empty panel. |

The cache holds **only the same usage figures already displayed in the panel**. It contains no token, no credential, and no request or response body. Entries older than 12 hours are discarded on load, because a stale percentage is more misleading than none. Delete the file at any time; Cadence just refetches.

See [`Cadence/Services/UsageCache.swift`](Cadence/Services/UsageCache.swift) — it's about 50 lines, and the `Codable` type it writes is visible in full.

## Signing, notarization, and the sandbox

Releases **from v2.2 onward** are signed with a **Developer ID certificate**, built with the **Hardened Runtime** enabled, and **notarized by Apple**. They open normally — no `xattr` incantation, no right-click-Open dance. (Earlier releases were ad-hoc signed and required manually clearing the quarantine flag; if you installed one of those, upgrading is worth it.)

Cadence is **not** sandboxed (`ENABLE_APP_SANDBOX = NO`), and cannot be:

- **Launching subprocesses** (`ccusage` / `npx`) is forbidden inside the App Sandbox.
- **Reading another app's Keychain item** (`Claude Code-credentials`) requires access the sandbox does not grant.

These are independent settings, and it's worth being precise because they're easy to conflate: the **sandbox** is what would block the subprocess and the Keychain read, while the **Hardened Runtime** blocks code injection, unsigned memory, and library hijacking. Cadence needs the former off and gets the latter's protections for free — so the app is notarizable *and* hardened against tampering, without giving up what it needs to work.

You can confirm all of this on the downloaded app yourself:

```bash
# Notarization ticket is stapled and valid:
xcrun stapler validate /Applications/Cadence.app

# Gatekeeper accepts it, and it's signed by a Developer ID, not ad-hoc:
spctl --assess --type execute --verbose=4 /Applications/Cadence.app
codesign -dv --verbose=4 /Applications/Cadence.app 2>&1 | grep -E 'Authority|flags'
```

The `flags=0x10000(runtime)` in that last output is the Hardened Runtime. Builds from source are ad-hoc signed and won't show a Developer ID authority — that's expected, and it means the binary you run is the code you just read.

## Verify it yourself

Don't take our word for it. From a clone of the repo:

```bash
# 1. Every network endpoint the app can reach.
#    Expect exactly one: api.anthropic.com/api/oauth/usage
grep -rn 'URL(string' Cadence --include='*.swift'

# 2. Every subprocess / shell invocation.
#    Expect only /bin/zsh (to locate the binary) and the ccusage/npx path.
grep -rniE 'Process\(|executableURL|/bin/|npx|launchPath' Cadence --include='*.swift'

# 3. Confirm nothing is ever logged. Expect ZERO results — there is no
#    logging in Cadence at all, so a token cannot leak into Console.app.
grep -rniE 'print\(|NSLog|os_log|Logger\(' Cadence --include='*.swift'

# 4. Every disk write. Expect hits in exactly one file, UsageCache.swift.
grep -rn 'FileManager\|\.write(' Cadence --include='*.swift'

# 5. Prove the token never reaches that file: the cache's Codable types
#    are UsageSnapshot / UsageLimits, and neither has a credential field.
grep -rn 'struct CachedUsage' -A 5 Cadence/Services/UsageCache.swift
```

Check #4 is the one worth doing carefully rather than trusting. It should point only at `UsageCache.swift`, and everything it writes is defined by the `CachedUsage` struct that #5 prints — usage figures and a timestamp. The token lives in `ClaudeCredentials`/`UsageLimitsService`, which appear nowhere in that output.

At runtime, point a network monitor (Little Snitch, LuLu, or `Console.app`) at Cadence and confirm the only host it talks to is `api.anthropic.com`. You can also watch the Keychain claim stay quiet: leave Cadence running and confirm no permission dialog ever appears on its own.

## Reporting a vulnerability

If you find a security issue, **please do not open a public issue.** Instead:

- Use GitHub's **[private vulnerability reporting](https://github.com/MatiasPC/Cadence/security/advisories/new)** (Security → Report a vulnerability), or
- Email the maintainer directly.

We'll acknowledge within a few days and credit you (if you'd like) once a fix ships.

## Supported versions

Cadence is a small, actively developed hobby project. Security fixes land on `main` and in the latest release. Please run the newest version before reporting.
