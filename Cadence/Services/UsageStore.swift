import Foundation
import Observation

enum LoadStatus: Equatable {
    case idle, loading, loaded, failed
}

/// What the compact menu-bar label shows.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case sessionPct, weekPct, sessionCost

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sessionPct:  return "Session %"
        case .weekPct:     return "Week %"
        case .sessionCost: return "Session cost"
        }
    }
}

/// App-wide state: polls ccusage on a timer and exposes a single `UsageSnapshot`
/// the views render. Everything is main-actor; the subprocess work happens inside
/// `CCUsageClient` off the main thread.
@MainActor
@Observable
final class UsageStore {

    private(set) var snapshot = UsageSnapshot()
    /// Real plan-limit utilization from Claude Code's auth, when available.
    private(set) var limits: UsageLimits?
    private(set) var status: LoadStatus = .idle
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    var menuBarMetric: MenuBarMetric {
        didSet { UserDefaults.standard.set(menuBarMetric.rawValue, forKey: "menuBarMetric") }
    }

    private let refreshSeconds: UInt64 = 60
    private let client = CCUsageClient()
    private let limitsService = UsageLimitsService()
    private var ticker: Task<Void, Never>?

    init() {
        let raw = UserDefaults.standard.string(forKey: "menuBarMetric") ?? ""
        menuBarMetric = MenuBarMetric(rawValue: raw) ?? .sessionPct
        start()
    }

    func start() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: (self?.refreshSeconds ?? 60) * 1_000_000_000)
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    func refresh() async {
        if status != .loaded { status = .loading }

        // Real plan limits fetch in parallel and are independent of ccusage.
        async let limitsResult = limitsService.fetch()

        do {
            let (blocks, daily) = try await client.fetch()
            snapshot = Self.buildSnapshot(blocks: blocks, daily: daily)
            errorMessage = nil
            status = .loaded
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
            status = .failed
        }

        if let fetched = await limitsResult { limits = fetched }
    }

    // MARK: - Usage bars (real plan limits, else time-based fallback)

    /// True once we've successfully read real plan-limit data at least once.
    var hasRealLimits: Bool { limits?.fiveHour != nil }

    var sessionProgress: Double {
        limits?.fiveHour?.utilization ?? snapshot.block?.timeProgress ?? 0
    }
    var sessionResetsAt: Date? {
        limits?.fiveHour?.resetsAt ?? snapshot.block?.endTime
    }
    var weekLimitProgress: Double {
        limits?.sevenDay?.utilization ?? snapshot.weekProgress
    }
    var weekResetsAt: Date? { limits?.sevenDay?.resetsAt }
    var opusWeekProgress: Double? { limits?.sevenDayOpus?.utilization }

    // MARK: - Menu-bar label

    var menuBarText: String {
        switch menuBarMetric {
        case .sessionPct:  return Self.pct(limits?.fiveHour)
        case .weekPct:     return Self.pct(limits?.sevenDay)
        case .sessionCost: return Format.money(snapshot.block?.cost ?? 0, compact: true)
        }
    }

    private static func pct(_ window: LimitWindow?) -> String {
        guard let window else { return "—" }
        return "\(Int((window.utilization * 100).rounded()))%"
    }

    // MARK: - Snapshot assembly

    private static func buildSnapshot(blocks: BlocksReport, daily: DailyReport) -> UsageSnapshot {
        var snap = UsageSnapshot()

        if let active = blocks.blocks.first(where: { $0.isActive }) {
            snap.block = BlockView(block: active)
        }

        // Index daily rows by their date string for O(1) lookups.
        let byDate = Dictionary(daily.daily.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        let today = fmt.string(from: Date())

        if let todayRow = byDate[today] {
            snap.todayCost = todayRow.totalCost
            snap.todayTokens = todayRow.totalTokens
            snap.modelShares = Self.modelShares(from: todayRow)
        }

        // Current calendar week: total spend so far + fraction of the week elapsed.
        if let week = cal.dateInterval(of: .weekOfYear, for: Date()) {
            snap.weekCost = daily.daily.reduce(0) { sum, row in
                guard let d = fmt.date(from: row.date), week.contains(d) else { return sum }
                return sum + row.totalCost
            }
            let elapsed = Date().timeIntervalSince(week.start)
            snap.weekProgress = min(max(elapsed / week.duration, 0), 1)
        }

        snap.allTimeCost = daily.totals.totalCost
        return snap
    }

    private static func modelShares(from row: DailyRow) -> [ModelShare] {
        var byFamily: [ModelFamily: (cost: Double, tokens: Int)] = [:]
        for b in row.modelBreakdowns {
            let fam = ModelFamily.classify(b.modelName)
            byFamily[fam, default: (0, 0)].cost += b.cost
            byFamily[fam, default: (0, 0)].tokens += b.totalTokens
        }
        return byFamily
            .map { ModelShare(family: $0.key, cost: $0.value.cost, tokens: $0.value.tokens) }
            .sorted { $0.cost > $1.cost }
    }
}
