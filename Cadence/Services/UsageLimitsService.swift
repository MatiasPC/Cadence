import Foundation
import Security

/// Fetches real plan-limit utilization — the same numbers Claude Code's `/usage`
/// shows — by reusing Claude Code's stored OAuth token to call the endpoint it
/// uses internally: `GET https://api.anthropic.com/api/oauth/usage`.
///
/// Everything is best-effort: any missing token / network / shape problem
/// returns `nil`, and the UI falls back to its time-based bars.
actor UsageLimitsService {

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetch() async -> UsageLimits? {
        guard let token = ClaudeCredentials.accessToken() else { return nil }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return Self.parse(data)
        } catch {
            return nil
        }
    }

    /// Tolerant hand-parse — the endpoint is undocumented, so we defensively pull
    /// fields rather than binding to a strict schema.
    private static func parse(_ data: Data) -> UsageLimits? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return UsageLimits(
            fiveHour: window(root["five_hour"]),
            sevenDay: window(root["seven_day"]),
            sevenDayOpus: window(root["seven_day_opus"])
        )
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

/// Reads Claude Code's OAuth access token from the macOS Keychain
/// (`Claude Code-credentials`). The first read triggers a one-time system
/// "allow access" prompt; choosing "Always Allow" makes later reads silent.
enum ClaudeCredentials {
    static func accessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Stored as {"claudeAiOauth": {"accessToken": ...}}; tolerate a flat shape too.
        let oauth = (root["claudeAiOauth"] as? [String: Any]) ?? root
        return oauth["accessToken"] as? String
    }
}
