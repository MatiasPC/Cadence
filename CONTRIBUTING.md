# Contributing to Cadence

Thanks for your interest in improving Cadence! This is a small, focused project, so contributions of all sizes are welcome — bug fixes, refinements, docs, and well-scoped features.

## Development setup

```bash
git clone https://github.com/MatiasPC/Cadence.git
cd Cadence
open Cadence.xcodeproj      # DesignSystem resolves from GitHub automatically
```

Select the **Cadence** scheme and press ⌘R. That's it — no extra tooling required to build.

**Requirements:** macOS 26+, Xcode 26+, and (at runtime) Node.js + [`ccusage`](https://github.com/ryoppippi/ccusage).

## Project layout (XcodeGen)

The Xcode project is generated from [`project.yml`](project.yml) by [XcodeGen](https://github.com/yonaskolb/XcodeGen). **`project.yml` is the source of truth.** The generated `Cadence.xcodeproj` is committed so the app builds without installing XcodeGen — but if you change project settings, dependencies, or add files at the top level, regenerate it:

```bash
brew install xcodegen      # once
xcodegen generate          # after editing project.yml
```

Commit the regenerated `.xcodeproj` alongside your `project.yml` change.

## Code signing (optional, but recommended locally)

Builds are ad-hoc signed by default, which needs no certificate. The catch: an
ad-hoc signature's designated requirement is a bare `cdhash`, so **every rebuild
looks like a different app to macOS** — and the Keychain ACL guarding Claude
Code's token is keyed on that requirement. The result is that "Always Allow" is
forgotten every time you rebuild.

To make it stick, create `Cadence/Config/Local.xcconfig` (gitignored):

```
CODE_SIGN_IDENTITY = <SHA-1 from: security find-identity -v -p codesigning>
DEVELOPMENT_TEAM = <your team ID>
CODE_SIGNING_REQUIRED = YES
```

Use the certificate's SHA-1 hash, not the name `Apple Development` — for macOS
targets Xcode resolves that name to `Mac Development` and fails to match.

## Architecture

A clean, small SwiftUI menu-bar app:

```
Cadence/
├── App/           CadenceApp — the MenuBarExtra entry point
├── Models/        Usage.swift — Codable ccusage models + UI-facing snapshot
├── Config/        Signing.xcconfig (+ gitignored Local.xcconfig)
├── Services/
│   ├── CCUsageClient      runs the ccusage CLI (off-main, actor-isolated)
│   ├── ClaudeCredentials  silent Keychain reads of Claude Code's token
│   ├── UsageLimitsService token caching → real plan limits
│   ├── UsageCache         last-good state persisted across launches
│   └── UsageStore         @MainActor @Observable state; tiered polling loop
├── Views/         UsagePanelView + Components/ (the panel UI)
└── Design/        Format + PanelColor helpers
```

- **Concurrency:** all UI state is `@MainActor`; subprocess and network work happens off the main thread inside actors. Keep it that way — don't block the main actor on I/O.
- **Polling is tiered.** `blocks` is cheap and runs every 60s; `daily` scans all history and fetches live pricing (~3.5s), so it runs every 5 minutes. Don't collapse them back into one interval. ccusage's `--offline` flag looks like an easy 60x win here, but its bundled pricing table returns **0** for current models — don't add it.
- **Keychain reads are silent by default** (see `ClaudeCredentials`). Only an explicit user action may raise the system permission panel; a background poll never should.
- **UI:** Cadence uses the [Velvet UI](https://github.com/MatiasPC/velvet-ui) design system (`DSColors`, `DSSpacing`, `DSRadius`, …). Prefer DS tokens over hardcoded colors, spacing, and radii.

## Coding conventions

- Swift 6, strict concurrency. Code should compile without concurrency warnings.
- Match the surrounding style: concise doc comments on non-obvious types/functions, no dead code.
- Keep the security posture intact — see [SECURITY.md](SECURITY.md). Any new network call, subprocess, or credential access **must** be justified and documented there in the same PR.

## Pull requests

1. Fork and branch from `main` (e.g. `fix/burn-rate-rounding`).
2. Make focused commits with clear messages.
3. Ensure the app **builds** (`xcodebuild -project Cadence.xcodeproj -scheme Cadence build`) before opening the PR.
4. Describe *what* changed and *why*. Screenshots help for UI changes.

## Reporting bugs & ideas

Open a [GitHub issue](https://github.com/MatiasPC/Cadence/issues). For **security** issues, follow [SECURITY.md](SECURITY.md) instead of filing a public issue.
