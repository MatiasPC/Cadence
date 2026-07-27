import Foundation
import Observation
import AppKit

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

/// Holds a notification token so `deinit`, which is nonisolated, can reach it
/// without touching main-actor state.
private final class ObserverToken: @unchecked Sendable {
    var value: (any NSObjectProtocol)?
}

/// App-wide state: polls ccusage on a timer and exposes a single `UsageSnapshot`
/// the views render. Everything is main-actor; the subprocess work happens inside
/// `CCUsageClient` off the main thread.
///
/// Two things keep this cheap. The last good result is persisted, so a relaunch
/// paints real numbers before the first fetch returns. And the two ccusage
/// queries run on different cadences — the active block is polled every minute,
/// while the full daily report (which is network-bound and scans all history)
/// runs every few minutes.
@MainActor
@Observable
final class UsageStore {

    private(set) var snapshot = UsageSnapshot()
    /// Real plan-limit utilization from Claude Code's auth, when available.
    private(set) var limits: UsageLimits?
    /// Why `limits` is missing, when it is — drives the panel's prompt row.
    private(set) var limitsProblem: LimitsUnavailable?
    private(set) var status: LoadStatus = .idle
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    var menuBarMetric: MenuBarMetric {
        didSet { UserDefaults.standard.set(menuBarMetric.rawValue, forKey: "menuBarMetric") }
    }

    /// The active block changes constantly and is cheap to read.
    private let fastInterval: TimeInterval = 60
    /// The daily report barely moves minute to minute and costs ~60x more.
    private let dailyInterval: TimeInterval = 5 * 60

    private let client = CCUsageClient()
    private let limitsService = UsageLimitsService()
    private var ticker: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var lastDailyFetch: Date?
    private var cachedDaily: DailyReport?
    /// `deinit` is nonisolated under Swift 6, so this token can't live on the
    /// actor. It's written once during init and read once on teardown.
    nonisolated private let wakeObserver = ObserverToken()

    init() {
        let raw = UserDefaults.standard.string(forKey: "menuBarMetric") ?? ""
        menuBarMetric = MenuBarMetric(rawValue: raw) ?? .sessionPct

        // Paint last session's numbers immediately; the first fetch replaces them.
        if let cached = UsageCache.load() {
            snapshot = cached.snapshot
            limits = cached.limits
            lastUpdated = cached.savedAt
            status = .loaded
        }

        observeWake()
        start()
    }

    deinit {
        if let token = wakeObserver.value {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    // MARK: - Scheduling

    func start() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.fastInterval ?? 60
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    /// Sleeping suspends the poll loop's timer, so the first tick after waking can
    /// be arbitrarily late. Refresh immediately instead of showing stale numbers.
    private func observeWake() {
        wakeObserver.value = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    // MARK: - Fetching

    /// Coalesces concurrent callers — the poll loop, the panel appearing, and the
    /// refresh button can all land at once, and each extra run costs a subprocess.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await performRefresh() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performRefresh() async {
        if status != .loaded { status = .loading }

        // Real plan limits are independent of ccusage, so let them run in parallel.
        async let limitsResult = limitsService.fetch()

        do {
            let blocks = try await client.fetchBlocks()
            let daily = try await currentDaily()
            snapshot = Self.buildSnapshot(blocks: blocks, daily: daily)
            errorMessage = nil
            status = .loaded
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
            // Keep showing cached numbers rather than blanking the panel; the
            // footer timestamp already tells the user how old they are.
            if snapshot == UsageSnapshot() { status = .failed }
        }

        switch await limitsResult {
        case .success(let fetched):
            limits = fetched
            limitsProblem = nil
        case .failure(let problem):
            limitsProblem = problem
        }

        UsageCache.save(snapshot: snapshot, limits: limits)
    }

    /// Returns the daily report, reusing the last one until it goes stale.
    private func currentDaily() async throws -> DailyReport {
        let isStale = lastDailyFetch.map { Date().timeIntervalSince($0) >= dailyInterval } ?? true
        guard isStale || cachedDaily == nil else { return cachedDaily! }

        do {
            let daily = try await client.fetchDaily()
            cachedDaily = daily
            lastDailyFetch = Date()
            return daily
        } catch {
            if let cachedDaily { return cachedDaily }
            throw error
        }
    }

    /// Re-reads the Keychain with the system permission panel allowed. Only call
    /// this from a user action — it can put up a blocking dialog.
    func grantKeychainAccess() async {
        switch await limitsService.fetchAllowingPrompt() {
        case .success(let fetched):
            limits = fetched
            limitsProblem = nil
            UsageCache.save(snapshot: snapshot, limits: limits)
        case .failure(let problem):
            limitsProblem = problem
        }
    }

    // MARK: - Usage bars (real plan limits, else time-based fallback)

    /// True once we've successfully read real plan-limit data at least once.
    var hasRealLimits: Bool { limits?.fiveHour != nil }

    /// True when the user needs to approve Keychain access to see real limits.
    var needsKeychainPermission: Bool { limitsProblem == .needsKeychainPermission }

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

    /// Falls back to a real cost figure rather than a placeholder: without plan
    /// limits a percentage would either be a dash or a time-based number dressed
    /// up as a limit, and both read as "the app is broken".
    var menuBarText: String {
        switch menuBarMetric {
        case .sessionPct:
            if let window = limits?.fiveHour { return Self.pct(window) }
            return Format.money(snapshot.block?.cost ?? 0, compact: true)
        case .weekPct:
            if let window = limits?.sevenDay { return Self.pct(window) }
            return Format.money(snapshot.weekCost, compact: true)
        case .sessionCost:
            return Format.money(snapshot.block?.cost ?? 0, compact: true)
        }
    }

    private static func pct(_ window: LimitWindow) -> String {
        "\(Int((window.utilization * 100).rounded()))%"
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
            if !snap.modelShares.isEmpty {
                snap.modelShareDate = todayRow.date
            }
        }

        if snap.modelShares.isEmpty {
            let rowsByDateDescending = daily.daily.sorted { $0.date > $1.date }
            if let latestModelRow = rowsByDateDescending.first(where: { !Self.modelShares(from: $0).isEmpty }) {
                snap.modelShares = Self.modelShares(from: latestModelRow)
                snap.modelShareDate = latestModelRow.date
            }
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
