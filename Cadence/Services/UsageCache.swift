import Foundation

/// Last known good state, persisted so a relaunch shows real numbers
/// immediately instead of an empty panel and a "—" in the menu bar.
///
/// This is a display cache, not a source of truth: it is written after every
/// successful fetch and read once at launch. A corrupt or unreadable file is
/// simply ignored — we fall back to an empty state and refetch.
struct CachedUsage: Codable {
    var snapshot: UsageSnapshot
    var limits: UsageLimits?
    var savedAt: Date
}

enum UsageCache {

    /// Cached values older than this are dropped: a stale 5-hour block or week
    /// percentage is more misleading than showing nothing.
    private static let maxAge: TimeInterval = 12 * 60 * 60

    private static var fileURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("Cadence", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-cache.json")
    }

    static func load() -> CachedUsage? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cached = try? decoder.decode(CachedUsage.self, from: data) else { return nil }
        guard Date().timeIntervalSince(cached.savedAt) < maxAge else { return nil }
        return cached
    }

    static func save(snapshot: UsageSnapshot, limits: UsageLimits?) {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = CachedUsage(snapshot: snapshot, limits: limits, savedAt: Date())
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
