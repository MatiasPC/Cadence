import Foundation

enum CCUsageError: LocalizedError {
    /// Neither a global `ccusage` nor `npx` could be found.
    case notFound
    /// The process ran but exited non-zero (message is stderr).
    case failed(String)
    /// Output could not be decoded as the expected JSON.
    case decode(String)
    /// The process outlived its deadline and was killed.
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "ccusage not found. Install Node, then run: npm install -g ccusage"
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
/// A launched `.app` inherits a minimal PATH, so on first use we resolve the
/// binary through a login shell (`command -v ccusage || command -v npx`) and
/// cache the result. A global `ccusage` is preferred; otherwise we fall back to
/// `npx --yes ccusage`, which is slower on the first call but needs no install.
actor CCUsageClient {

    private struct Command {
        let launchPath: String
        let leadingArgs: [String]
    }

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
        let data = try await runRaw(
            launchPath: "/bin/zsh",
            args: ["-lc", "command -v ccusage || command -v npx"]
        )
        let path = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !path.isEmpty else { throw CCUsageError.notFound }

        let resolved: Command = path.hasSuffix("/ccusage")
            ? Command(launchPath: path, leadingArgs: [])
            : Command(launchPath: path, leadingArgs: ["--yes", "ccusage"])
        command = resolved
        return resolved
    }

    // MARK: - Process execution

    private func run<T: Decodable>(_ args: [String]) async throws -> T {
        let cmd = try await resolvedCommand()
        let data = try await runRaw(launchPath: cmd.launchPath, args: cmd.leadingArgs + args)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw CCUsageError.decode(error.localizedDescription)
        }
    }

    /// Launches a process off the actor's executor and returns its stdout.
    /// stdout is drained on a background thread before `waitUntilExit` to avoid
    /// a pipe-buffer deadlock on large JSON payloads.
    private func runRaw(launchPath: String, args: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = args

                // Ensure node (and npx) are discoverable regardless of the app's PATH.
                var env = ProcessInfo.processInfo.environment
                let extras = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
                env["PATH"] = env["PATH"].map { "\($0):\(extras)" } ?? extras
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
