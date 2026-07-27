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

    private enum CodingKeys: String, CodingKey {
        case daily, data, totals, summary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        daily = try c.decodeIfPresent([DailyRow].self, forKey: .daily)
            ?? c.decodeIfPresent([DailyRow].self, forKey: .data)
            ?? []
        totals = try c.decodeIfPresent(Totals.self, forKey: .totals)
            ?? c.decodeIfPresent(Totals.self, forKey: .summary)
            ?? Totals()
    }
}

/// One calendar day of usage. ccusage v20 keys the date as `period`; older
/// builds used `date` — decode either so a differently-versioned global install
/// still works.
struct DailyRow: Decodable {
    let date: String
    let totalCost: Double
    let totalTokens: Int
    let modelsUsed: [String]
    let modelBreakdowns: [ModelBreakdown]

    private enum CodingKeys: String, CodingKey {
        case period, date, totalCost, costUSD, totalTokens
        case modelsUsed, models, modelBreakdowns, breakdown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .period)
            ?? c.decode(String.self, forKey: .date)
        totalCost = try c.decodeIfPresent(Double.self, forKey: .totalCost)
            ?? c.decodeIfPresent(Double.self, forKey: .costUSD)
            ?? 0
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        modelsUsed = try c.decodeIfPresent([String].self, forKey: .modelsUsed)
            ?? c.decodeIfPresent([String].self, forKey: .models)
            ?? []

        let arrayBreakdowns = try c.decodeIfPresent([ModelBreakdown].self, forKey: .modelBreakdowns)
        let keyedBreakdowns = try c.decodeIfPresent([String: ModelBreakdownValues].self, forKey: .breakdown)?
            .map { ModelBreakdown(modelName: $0.key, values: $0.value) }
        modelBreakdowns = arrayBreakdowns ?? keyedBreakdowns ?? []
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

    private enum CodingKeys: String, CodingKey {
        case modelName, cost, costUSD
        case inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens
    }

    init(
        modelName: String,
        cost: Double,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int
    ) {
        self.modelName = modelName
        self.cost = cost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
    }

    init(modelName: String, values: ModelBreakdownValues) {
        self.init(
            modelName: modelName,
            cost: values.cost,
            inputTokens: values.inputTokens,
            outputTokens: values.outputTokens,
            cacheCreationTokens: values.cacheCreationTokens,
            cacheReadTokens: values.cacheReadTokens
        )
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modelName = try c.decode(String.self, forKey: .modelName)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
            ?? c.decodeIfPresent(Double.self, forKey: .costUSD)
            ?? 0
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
    }
}

struct ModelBreakdownValues: Decodable {
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    private enum CodingKeys: String, CodingKey {
        case cost, costUSD
        case inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
            ?? c.decodeIfPresent(Double.self, forKey: .costUSD)
            ?? 0
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
    }
}

struct Totals: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalCost: Double
    let totalTokens: Int

    private enum CodingKeys: String, CodingKey {
        case inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens
        case totalCost, totalCostUSD, costUSD, totalTokens
    }

    init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0,
        totalCost: Double = 0,
        totalTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalCost = totalCost
        self.totalTokens = totalTokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
        totalCost = try c.decodeIfPresent(Double.self, forKey: .totalCost)
            ?? c.decodeIfPresent(Double.self, forKey: .totalCostUSD)
            ?? c.decodeIfPresent(Double.self, forKey: .costUSD)
            ?? 0
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens)
            ?? inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}

// MARK: - Real plan-limit usage (Claude Code's /api/oauth/usage)

/// Plan-limit utilization for the rolling windows Claude Code's `/usage` shows.
struct UsageLimits: Equatable, Codable {
    var fiveHour: LimitWindow?
    var sevenDay: LimitWindow?
    var sevenDayOpus: LimitWindow?
}

struct LimitWindow: Equatable, Codable {
    /// 0...1 fraction of the window's limit consumed.
    let utilization: Double
    let resetsAt: Date?
}

// MARK: - Model families (for the Opus/Sonnet split)

enum ModelFamily: String, CaseIterable, Codable {
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
struct ModelShare: Identifiable, Codable {
    let family: ModelFamily
    let cost: Double
    let tokens: Int
    var id: String { family.rawValue }
}

// MARK: - UI-facing aggregate

/// Everything the panel needs, assembled from the two ccusage reports.
/// `UsageStore` produces this; the views only ever read it.
struct UsageSnapshot: Equatable, Codable {
    var block: BlockView?
    var todayCost: Double = 0
    var todayTokens: Int = 0
    /// Total spend across the current calendar week (its days so far).
    var weekCost: Double = 0
    /// 0...1 fraction of the current calendar week elapsed.
    var weekProgress: Double = 0
    var modelShares: [ModelShare] = []
    var modelShareDate: String?
    var allTimeCost: Double = 0

    var modelShareHeading: String {
        guard let modelShareDate else { return "TODAY BY MODEL" }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return modelShareDate == fmt.string(from: Date())
            ? "TODAY BY MODEL"
            : "LATEST DAY BY MODEL"
    }

    static func == (lhs: UsageSnapshot, rhs: UsageSnapshot) -> Bool {
        lhs.block == rhs.block
            && lhs.todayCost == rhs.todayCost
            && lhs.todayTokens == rhs.todayTokens
            && lhs.weekCost == rhs.weekCost
            && lhs.weekProgress == rhs.weekProgress
            && lhs.allTimeCost == rhs.allTimeCost
            && lhs.modelShareDate == rhs.modelShareDate
            && lhs.modelShares.map(\.id) == rhs.modelShares.map(\.id)
            && lhs.modelShares.map(\.cost) == rhs.modelShares.map(\.cost)
    }
}

/// Flattened, view-friendly projection of the active block.
struct BlockView: Equatable, Codable {
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
