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

## Architecture

A clean, small SwiftUI menu-bar app:

```
Cadence/
├── App/           CadenceApp — the MenuBarExtra entry point
├── Models/        Usage.swift — Codable ccusage models + UI-facing snapshot
├── Services/
│   ├── CCUsageClient      runs the ccusage CLI (off-main, actor-isolated)
│   ├── UsageLimitsService reads the Keychain token → real plan limits
│   └── UsageStore         @MainActor @Observable state; 60s polling loop
├── Views/         UsagePanelView + Components/ (the panel UI)
└── Design/        Format + PanelColor helpers
```

- **Concurrency:** all UI state is `@MainActor`; subprocess and network work happens off the main thread inside actors. Keep it that way — don't block the main actor on I/O.
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
