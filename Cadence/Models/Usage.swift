import Foundation

// MARK: - ccusage JSON: `ccusage blocks --active --json`

/// Wrapper for the `blocks` command output.
struct BlocksReport: Decodable {
    let blocks: [ActiveBlock]
}

/// A rolling 5-hour billing block. When `--active` is passed there is at most one.
struct ActiveBlock: Decodable {
    let costUSD: Double
    let totalTokens: Int
    let tokenCounts: TokenCounts
    let startTime: Date
    let endTime: Date
    let isActive: Bool
    let models: [String]
    let burnRate: BurnRate?
    let projection: Projection?
}

struct TokenCounts: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int
}

struct BurnRate: Decodable {
    let costPerHour: Double
    let tokensPerMinute: Double
}

struct Projection: Decodable {
    let remainingMinutes: Int
    let totalCost: Double
    let totalTokens: Int
}

// MARK: - ccusage JSON: `ccusage daily --json`

struct DailyReport: Decodable {
    let daily: [DailyRow]
    let totals: Totals
}

/// One calendar day of usage. ccusage v20 keys the date as `period`; older
/// builds used `date` — decode either so a differently-versioned global install
/// still works.
struct DailyRow: Decodable {
    let date: String
    let totalCost: Double
    let totalTokens: Int
    let modelBreakdowns: [ModelBreakdown]

    private enum CodingKeys: String, CodingKey {
        case period, date, totalCost, totalTokens, modelBreakdowns
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .period)
            ?? c.decode(String.self, forKey: .date)
        totalCost = try c.decode(Double.self, forKey: .totalCost)
        totalTokens = try c.decode(Int.self, forKey: .totalTokens)
        modelBreakdowns = try c.decodeIfPresent([ModelBreakdown].self, forKey: .modelBreakdowns) ?? []
    }
}

struct ModelBreakdown: Decodable {
    let modelName: String
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
}

struct Totals: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalCost: Double
    let totalTokens: Int
}

// MARK: - Real plan-limit usage (Claude Code's /api/oauth/usage)

/// Plan-limit utilization for the rolling windows Claude Code's `/usage` shows.
struct UsageLimits: Equatable {
    var fiveHour: LimitWindow?
    var sevenDay: LimitWindow?
    var sevenDayOpus: LimitWindow?
}

struct LimitWindow: Equatable {
    /// 0...1 fraction of the window's limit consumed.
    let utilization: Double
    let resetsAt: Date?
}

// MARK: - Model families (for the Opus/Sonnet split)

enum ModelFamily: String, CaseIterable {
    case opus = "Opus"
    case sonnet = "Sonnet"
    case haiku = "Haiku"
    case other = "Other"

    static func classify(_ modelName: String) -> ModelFamily {
        let n = modelName.lowercased()
        if n.contains("opus") { return .opus }
        if n.contains("sonnet") { return .sonnet }
        if n.contains("haiku") { return .haiku }
        return .other
    }
}

/// A single model's share of today's spend, ready for the split bar.
struct ModelShare: Identifiable {
    let family: ModelFamily
    let cost: Double
    let tokens: Int
    var id: String { family.rawValue }
}

// MARK: - UI-facing aggregate

/// Everything the panel needs, assembled from the two ccusage reports.
/// `UsageStore` produces this; the views only ever read it.
struct UsageSnapshot: Equatable {
    var block: BlockView?
    var todayCost: Double = 0
    var todayTokens: Int = 0
    /// Total spend across the current calendar week (its days so far).
    var weekCost: Double = 0
    /// 0...1 fraction of the current calendar week elapsed.
    var weekProgress: Double = 0
    var modelShares: [ModelShare] = []
    var allTimeCost: Double = 0

    static func == (lhs: UsageSnapshot, rhs: UsageSnapshot) -> Bool {
        lhs.block == rhs.block
            && lhs.todayCost == rhs.todayCost
            && lhs.todayTokens == rhs.todayTokens
            && lhs.weekCost == rhs.weekCost
            && lhs.weekProgress == rhs.weekProgress
            && lhs.allTimeCost == rhs.allTimeCost
            && lhs.modelShares.map(\.id) == rhs.modelShares.map(\.id)
            && lhs.modelShares.map(\.cost) == rhs.modelShares.map(\.cost)
    }
}

/// Flattened, view-friendly projection of the active block.
struct BlockView: Equatable {
    let cost: Double
    let tokens: Int
    let startTime: Date
    let endTime: Date
    let costPerHour: Double
    let projectedCost: Double
    let remainingMinutes: Int

    /// 0...1 fraction of the 5-hour window elapsed.
    var timeProgress: Double {
        let total = endTime.timeIntervalSince(startTime)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(startTime)
        return min(max(elapsed / total, 0), 1)
    }

    init(block: ActiveBlock) {
        cost = block.costUSD
        tokens = block.totalTokens
        startTime = block.startTime
        endTime = block.endTime
        costPerHour = block.burnRate?.costPerHour ?? 0
        projectedCost = block.projection?.totalCost ?? block.costUSD
        remainingMinutes = block.projection?.remainingMinutes
            ?? max(0, Int(block.endTime.timeIntervalSinceNow / 60))
    }
}
