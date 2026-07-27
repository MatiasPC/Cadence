import Foundation

/// Why real plan limits aren't available, when they aren't.
enum LimitsUnavailable: Error, Equatable {
    /// Keychain access to Claude Code's token needs the user's approval.
    case needsKeychainPermission
    /// Claude Code isn't logged in on this machine.
    case notLoggedIn
    /// Token was rejected by the API — Claude Code likely re-authenticated.
    case tokenRejected
    /// Network or server problem; worth retrying.
    case unreachable
}

/// Fetches real plan-limit utilization — the same numbers Claude Code's `/usage`
/// shows — by reusing Claude Code's stored OAuth token to call the endpoint it
/// uses internally: `GET https://api.anthropic.com/api/oauth/usage`.
///
/// The token is cached in memory after the first successful read so routine
/// polling never touches the Keychain. We only go back to the Keychain when we
/// have no token or the API rejects the one we hold.
actor UsageLimitsService {

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private var cachedToken: String?

    /// Fetches limits, reading the Keychain silently if a token is needed.
    func fetch() async -> Result<UsageLimits, LimitsUnavailable> {
        await fetch(interactive: false)
    }

    /// Same, but permitted to raise the system Keychain panel. Call only from a
    /// user-initiated action.
    func fetchAllowingPrompt() async -> Result<UsageLimits, LimitsUnavailable> {
        // Force a fresh read so the prompt actually appears for the user.
        cachedToken = nil
        return await fetch(interactive: true)
    }

    private func fetch(interactive: Bool) async -> Result<UsageLimits, LimitsUnavailable> {
        let token: String
        switch currentToken(interactive: interactive) {
        case .success(let t): token = t
        case .failure(let problem): return .failure(problem)
        }

        switch await request(token: token) {
        case .success(let limits):
            return .success(limits)

        case .failure(.tokenRejected):
            // Claude Code rotates this token; a 401 means ours went stale, so
            // drop it and take exactly one more Keychain read to pick up the
            // replacement. Silent — a rotation must not spawn a dialog.
            cachedToken = nil
            guard case .token(let fresh) = ClaudeCredentials.read(), fresh != token else {
                return .failure(.tokenRejected)
            }
            cachedToken = fresh
            return await request(token: fresh)

        case .failure(let other):
            return .failure(other)
        }
    }

    /// Returns the cached token, reading the Keychain only when we don't hold one.
    /// Reads exactly once — in the interactive case a second read would mean a
    /// second system panel.
    private func currentToken(interactive: Bool) -> Result<String, LimitsUnavailable> {
        if let cachedToken { return .success(cachedToken) }

        let result = interactive
            ? ClaudeCredentials.readInteractively()
            : ClaudeCredentials.read()

        switch result {
        case .token(let token):
            cachedToken = token
            return .success(token)
        case .needsPermission:
            return .failure(.needsKeychainPermission)
        case .missing, .unreadable:
            return .failure(.notLoggedIn)
        }
    }

    private func request(token: String) async -> Result<UsageLimits, LimitsUnavailable> {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure(.unreachable) }
            switch http.statusCode {
            case 200:
                guard let limits = Self.parse(data) else { return .failure(.unreachable) }
                return .success(limits)
            case 401, 403:
                return .failure(.tokenRejected)
            default:
                return .failure(.unreachable)
            }
        } catch {
            return .failure(.unreachable)
        }
    }

    /// Tolerant hand-parse — the endpoint is undocumented, so we defensively pull
    /// fields rather than binding to a strict schema.
    private static func parse(_ data: Data) -> UsageLimits? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let limits = UsageLimits(
            fiveHour: window(root["five_hour"]),
            sevenDay: window(root["seven_day"]),
            sevenDayOpus: window(root["seven_day_opus"])
        )
        // An all-nil parse means the shape changed; treat it as a failure so we
        // keep showing the last good values instead of blanking the bars.
        guard limits.fiveHour != nil || limits.sevenDay != nil else { return nil }
        return limits
    }

    private static func window(_ any: Any?) -> LimitWindow? {
        guard let dict = any as? [String: Any] else { return nil }
        let raw = (dict["utilization"] as? NSNumber)?.doubleValue ?? 0
        // Accept either a 0–100 percentage or a 0–1 fraction.
        let fraction = raw > 1 ? raw / 100 : raw
        var reset: Date?
        if let s = dict["resets_at"] as? String { reset = Self.parseDate(s) }
        return LimitWindow(utilization: min(max(fraction, 0), 1), resetsAt: reset)
    }

    private static func parseDate(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let noFrac = ISO8601DateFormatter()
        noFrac.formatOptions = [.withInternetDateTime]
        return noFrac.date(from: s)
    }
}
