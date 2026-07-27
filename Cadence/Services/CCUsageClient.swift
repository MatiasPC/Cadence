import Foundation

enum CCUsageError: LocalizedError {
    /// Neither a global `ccusage` nor `npx` could be found. Carries the
    /// directories actually searched — "install Node" is unhelpful advice when
    /// Node is plainly installed but lives somewhere we didn't look.
    case notFound(searched: [String])
    /// The process ran but exited non-zero (message is stderr).
    case failed(String)
    /// Output could not be decoded as the expected JSON.
    case decode(String)
    /// The process outlived its deadline and was killed.
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notFound(let searched):
            let where_ = searched.isEmpty ? "" : "\nLooked in: \(searched.joined(separator: ", "))"
            return "Couldn't find ccusage or npx.\(where_)"
        case .failed(let m):
            return "ccusage failed: \(m)"
        case .decode(let m):
            return "Couldn't read ccusage output: \(m)"
        case .timedOut:
            return "ccusage took too long to respond."
        }
    }
}

/// A one-way flag set from the watchdog queue and read from the worker thread.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Runs the `ccusage` CLI and decodes its JSON.
///
/// Finding the binary is the hard part. An app launched from Finder inherits
/// launchd's `PATH` — typically just `/usr/bin:/bin:/usr/sbin:/sbin` — which
/// contains no Node installation of any kind. Worse, that inherited `PATH` can
/// be widened for a session (a `launchctl setenv` from a dotfile, say) and then
/// silently revert on the next reboot, which makes the app look like it "broke
/// after a restart".
///
/// So resolution never trusts the inherited environment. It asks the user's
/// shell, and falls back to probing known install locations:
///
///   1. `zsh -ilc` — **interactive** login shell. The `-i` matters: version
///      managers (nvm, fnm, volta, asdf, mise) initialize in `.zshrc`, and zsh
///      only sources `.zshrc` for interactive shells. A plain `-lc` sees
///      `.zprofile` but not `.zshrc`, so it misses them entirely.
///   2. `zsh -lc` — in case an exotic `.zshrc` misbehaves without a tty.
///   3. A direct scan of well-known directories, including nvm's versioned
///      ones, for setups where the shell tells us nothing.
///
/// The shell's own `PATH` is captured alongside the binary, because `ccusage`
/// is a Node script starting `#!/usr/bin/env node`. Finding it is not enough —
/// `node` has to be on the `PATH` we hand the child process, or it dies at the
/// shebang.
actor CCUsageClient {

    private struct Command {
        let launchPath: String
        let leadingArgs: [String]
        /// `PATH` for the child, so its `env node` shebang resolves.
        let searchPATH: String
    }

    /// Marker prefixes so a chatty `.zshrc` (banners, fastfetch, version
    /// notices) can't be mistaken for output. The previous implementation took
    /// the first line of stdout, which any such profile would have broken.
    private static let cmdMarker = "<<<CADENCE-CMD>>>"
    private static let pathMarker = "<<<CADENCE-PATH>>>"

    /// Always searched, regardless of what the shell reports: Homebrew on both
    /// architectures, the official Node installer, and MacPorts.
    private static let baseDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
        "/usr/bin",
        "/bin",
    ]

    private var command: Command?

    /// Hard ceiling on a single invocation. Without this a wedged `node` would
    /// leave the poll task suspended forever and the app would silently stop
    /// updating until relaunched.
    private static let processTimeout: TimeInterval = 30

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // Formatters are built inside the (@Sendable) closure so no non-Sendable
        // state is captured across concurrency domains under Swift 6.
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFrac.date(from: s) { return date }
            let noFrac = ISO8601DateFormatter()
            noFrac.formatOptions = [.withInternetDateTime]
            if let date = noFrac.date(from: s) { return date }
            throw CCUsageError.decode("bad date: \(s)")
        }
        return d
    }()

    // MARK: - Public API

    /// The active 5-hour block. Cheap relative to the daily report, so this is
    /// what the frequent poll uses.
    ///
    /// Note: ccusage's `--offline` flag would make this ~60x faster by skipping
    /// the live pricing fetch, but its bundled pricing table doesn't cover
    /// current models — every cost comes back as 0. Do not add it.
    func fetchBlocks() async throws -> BlocksReport {
        try await run(["blocks", "--active", "--json"])
    }

    /// The full daily report, including the per-model breakdown. Scans all
    /// history and fetches live pricing, so it runs on a slower cadence.
    func fetchDaily() async throws -> DailyReport {
        do {
            return try await run(["daily", "--json", "--breakdown"])
        } catch CCUsageError.failed(let message)
            where message.localizedCaseInsensitiveContains("breakdown") {
            return try await run(["daily", "--json"])
        }
    }

    // MARK: - Command resolution

    private func resolvedCommand() async throws -> Command {
        if let command { return command }

        // Interactive first so `.zshrc` (and any version manager in it) is read.
        for shellArgs in [["-ilc"], ["-lc"]] {
            if let found = try? await askShell(shellArgs) {
                command = found
                return found
            }
        }

        if let found = probeKnownDirectories() {
            command = found
            return found
        }

        throw CCUsageError.notFound(searched: searchedDirectories())
    }

    /// Asks a shell where `ccusage` (or `npx`) lives, and what its `PATH` is.
    private func askShell(_ shellArgs: [String]) async throws -> Command {
        let script = """
        cmd=$(command -v ccusage 2>/dev/null || command -v npx 2>/dev/null || true)
        printf '%s%s\\n' '\(Self.cmdMarker)' "$cmd"
        printf '%s%s\\n' '\(Self.pathMarker)' "$PATH"
        """
        let data = try await runRaw(
            launchPath: "/bin/zsh",
            args: shellArgs + [script],
            searchPATH: Self.baseDirectories.joined(separator: ":")
        )
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)

        func value(after marker: String) -> String? {
            lines.last { $0.hasPrefix(marker) }
                .map { String($0.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces) }
        }

        guard let binary = value(after: Self.cmdMarker), !binary.isEmpty,
              FileManager.default.isExecutableFile(atPath: binary)
        else { throw CCUsageError.notFound(searched: []) }

        let shellPATH = value(after: Self.pathMarker) ?? ""
        return makeCommand(binary: binary, extraPATH: shellPATH)
    }

    /// Last resort: look directly where Node tends to install things, for setups
    /// where the shell reports nothing useful.
    private func probeKnownDirectories() -> Command? {
        let fm = FileManager.default
        for directory in searchedDirectories() {
            // A global ccusage beats npx, which would re-download on every miss.
            for name in ["ccusage", "npx"] {
                let candidate = (directory as NSString).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: candidate) {
                    return makeCommand(binary: candidate, extraPATH: directory)
                }
            }
        }
        return nil
    }

    private func makeCommand(binary: String, extraPATH: String) -> Command {
        // The binary's own directory must be on PATH so `env node` resolves.
        let ownDirectory = (binary as NSString).deletingLastPathComponent
        let parts = [extraPATH, ownDirectory] + Self.baseDirectories
        var seen = Set<String>()
        let path = parts
            .flatMap { $0.split(separator: ":").map(String.init) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")

        return binary.hasSuffix("/ccusage")
            ? Command(launchPath: binary, leadingArgs: [], searchPATH: path)
            : Command(launchPath: binary, leadingArgs: ["--yes", "ccusage"], searchPATH: path)
    }

    /// Known install locations, most specific first. Version managers keep their
    /// shims outside any system directory, which is exactly why a launchd `PATH`
    /// never contains them.
    private func searchedDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var directories = [
            "\(home)/.volta/bin",
            "\(home)/.bun/bin",
            "\(home)/.asdf/shims",
            "\(home)/.local/share/fnm/aliases/default/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
        ]
        directories.append(contentsOf: nvmDirectories(home: home))
        directories.append(contentsOf: Self.baseDirectories)
        return directories
    }

    /// nvm installs per version under `~/.nvm/versions/node/<version>/bin` with
    /// no stable path, so prefer its `default` alias and otherwise take the
    /// highest version number.
    private func nvmDirectories(home: String) -> [String] {
        let root = "\(home)/.nvm/versions/node"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: root),
              !versions.isEmpty
        else { return [] }

        let sorted = versions.sorted {
            $0.compare($1, options: .numeric) == .orderedDescending
        }
        return sorted.map { "\(root)/\($0)/bin" }
    }

    // MARK: - Process execution

    private func run<T: Decodable>(_ args: [String]) async throws -> T {
        let cmd = try await resolvedCommand()
        let data = try await runRaw(
            launchPath: cmd.launchPath,
            args: cmd.leadingArgs + args,
            searchPATH: cmd.searchPATH
        )
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw CCUsageError.decode(error.localizedDescription)
        }
    }

    /// Launches a process off the actor's executor and returns its stdout.
    /// stdout is drained on a background thread before `waitUntilExit` to avoid
    /// a pipe-buffer deadlock on large JSON payloads.
    private func runRaw(
        launchPath: String,
        args: [String],
        searchPATH: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = args

                // `searchPATH` leads, since it came from the user's own shell or
                // from wherever the binary was actually found. The inherited
                // PATH is appended rather than trusted — under launchd it holds
                // no Node at all, and its contents vary between reboots.
                var env = ProcessInfo.processInfo.environment
                let inherited = env["PATH"].map { ":\($0)" } ?? ""
                env["PATH"] = searchPATH + inherited
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CCUsageError.failed(error.localizedDescription))
                    return
                }

                // Kill the process if it blows the deadline; the reads below then
                // hit EOF and we report the timeout rather than hanging.
                let killed = Flag()
                let watchdog = DispatchWorkItem {
                    guard process.isRunning else { return }
                    killed.set()
                    process.terminate()
                }
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + Self.processTimeout,
                    execute: watchdog
                )

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                if process.terminationStatus != 0 {
                    if killed.isSet {
                        continuation.resume(throwing: CCUsageError.timedOut)
                        return
                    }
                    let msg = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: CCUsageError.failed(
                        msg?.isEmpty == false ? msg! : "exit code \(process.terminationStatus)"
                    ))
                    return
                }
                continuation.resume(returning: outData)
            }
        }
    }
}
