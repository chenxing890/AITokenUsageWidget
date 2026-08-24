import Foundation

/// 三家供应商的用量抓取与解析。新增供应商时在 fetch(config:) 中添加分支。
enum UsageService {

    /// 并发抓取全部供应商（Widget 刷新用）
    static func fetchAll(configs: [ProviderConfig]) async -> [ProviderUsage] {
        await withTaskGroup(of: (Int, ProviderUsage).self) { group in
            for (index, config) in configs.enumerated() {
                group.addTask { (index, await fetch(config: config)) }
            }
            var results = [Int: ProviderUsage]()
            for await (index, usage) in group { results[index] = usage }
            return configs.indices.compactMap { results[$0] }
        }
    }

    /// 抓取单个供应商。Key 未填返回 missingKey；失败返回 error（中文提示）。
    static func fetch(config: ProviderConfig) async -> ProviderUsage {
        guard config.hasKey else {
            return ProviderUsage(
                kind: config.kind, displayName: config.name, state: .missingKey,
                currency: nil, totalBalance: nil, grantedBalance: nil,
                toppedUpBalance: nil, isAvailable: nil, windows: [], fetchedAt: Date()
            )
        }
        do {
            switch config.kind {
            case .deepseek: return try await fetchDeepSeek(config)
            case .kimi: return try await fetchKimi(config)
            case .glm: return try await fetchGLM(config)
            }
        } catch {
            return ProviderUsage(
                kind: config.kind, displayName: config.name,
                state: .error(APIClient.friendlyMessage(for: error)),
                currency: nil, totalBalance: nil, grantedBalance: nil,
                toppedUpBalance: nil, isAvailable: nil, windows: [], fetchedAt: Date()
            )
        }
    }

    // MARK: - DeepSeek（账户余额）

    /// GET /user/balance —— 总余额 / 赠送 / 充值 + 可用状态
    private static func fetchDeepSeek(_ config: ProviderConfig) async throws -> ProviderUsage {
        guard let url = config.apiURL(path: "/user/balance") else {
            throw APIClient.APIError.invalidURL
        }
        let json = try await APIClient.shared.get(
            url, headers: ["Authorization": "Bearer \(config.cleanAPIKey)"]
        )
        let info = json["balance_infos"]?[0]
        guard info?["total_balance"]?.double != nil else {
            // DeepSeek 错误也走 HTTP 401/403，这里只剩真正的空响应
            throw APIClient.APIError.emptyResponse
        }
        return ProviderUsage(
            kind: .deepseek, displayName: config.name, state: .ok,
            currency: info?["currency"]?.string,
            totalBalance: info?["total_balance"]?.double,
            grantedBalance: info?["granted_balance"]?.double,
            toppedUpBalance: info?["topped_up_balance"]?.double,
            isAvailable: json["is_available"]?.bool,
            windows: [], fetchedAt: Date()
        )
    }

    // MARK: - Kimi Code（5 小时 / 7 天 / 月度总额）

    /// GET /usages —— limits 中 duration=300 的为 5 小时窗口，顶层 usage 为 7 天窗口。
    /// 月度总额走非官方网页接口（需 kimi-auth Cookie，可选；失败不影响前两个窗口）。
    private static func fetchKimi(_ config: ProviderConfig) async throws -> ProviderUsage {
        guard let url = config.apiURL(path: "/usages") else {
            throw APIClient.APIError.invalidURL
        }
        let json = try await APIClient.shared.get(
            url,
            headers: ["Authorization": "Bearer \(config.apiKey)", "Accept": "application/json"]
        )

        var windows: [UsageWindow] = []
        // 5 小时窗口：limits[].window.duration == 300（单位：分钟）
        for limit in json["limits"]?.array ?? [] where limit["window"]?["duration"]?.double == 300 {
            if let window = makeWindow("5 小时", detail: limit["detail"]) {
                windows.append(window)
            }
        }
        // 7 天窗口：顶层 usage
        if let window = makeWindow("7 天", detail: json["usage"]) {
            windows.append(window)
        }
        // 月度总额（可选）：网页 billing 接口 totalQuota
        if config.hasExtraToken, let monthly = await fetchKimiMonthly(cookie: config.extraToken) {
            windows.append(monthly)
        }

        guard !windows.isEmpty else { throw APIClient.APIError.emptyResponse }
        return ProviderUsage(
            kind: .kimi, displayName: config.name, state: .ok,
            currency: nil, totalBalance: nil, grantedBalance: nil,
            toppedUpBalance: nil, isAvailable: nil,
            windows: windows, fetchedAt: Date()
        )
    }

    /// POST kimi.com 网页 billing 接口（kimi-auth Cookie），返回月度总额窗口。
    private static func fetchKimiMonthly(cookie: String) async -> UsageWindow? {
        guard let url = URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages") else {
            return nil
        }
        return try? await APIClient.shared.post(
            url,
            headers: ["Authorization": "Bearer \(cookie)", "Content-Type": "application/json"],
            body: Data("{}".utf8)
        )["totalQuota"].flatMap { makeWindow("本月总额", detail: $0) }
    }

    /// Kimi 窗口结构：{ limit, used, remaining, resetTime }，数字以字符串返回
    private static func makeWindow(_ title: String, detail: JSONValue?) -> UsageWindow? {
        guard let detail else { return nil }
        let limit = detail["limit"]?.double
        let used = detail["used"]?.double
            ?? limit.flatMap { $0 - (detail["remaining"]?.double ?? 0) }
        let percent: Double?
        if let used, let limit, limit > 0 {
            percent = min(used / limit * 100, 100)
        } else {
            percent = nil
        }
        return UsageWindow(
            title: title, usedPercent: percent, usedText: nil,
            resetTime: detail["resetTime"]?.isoDate
        )
    }

    // MARK: - GLM Coding（5 小时 / 7 天 / 月度工具）

    /// GET /api/monitor/usage/quota/limit
    /// TOKENS_LIMIT 只返回百分比（unit 3 = 5 小时，unit 6 = 7 天；缺 unit 时按重置时间排序），
    /// TIME_LIMIT 为月度工具额度，返回次数绝对值。
    private static func fetchGLM(_ config: ProviderConfig) async throws -> ProviderUsage {
        guard let url = config.apiURL(path: "/api/monitor/usage/quota/limit") else {
            throw APIClient.APIError.invalidURL
        }
        let json = try await APIClient.shared.get(
            url,
            headers: ["Authorization": config.cleanAPIKey, "Accept": "application/json"]
        )
        // GLM 鉴权/配额失败仍返回 HTTP 200，必须检查业务码并透出 msg
        if json["success"]?.bool == false
            || json["error"] != nil
            || (json["code"]?.int).map({ $0 != 200 }) == true {
            let msg = json["msg"]?.string
                ?? json["error"]?["message"]?.string
                ?? "接口返回错误"
            throw APIClient.APIError.message(msg)
        }
        let limits = json["data"]?["limits"]?.array ?? []
        guard !limits.isEmpty else { throw APIClient.APIError.emptyResponse }

        var windows: [UsageWindow] = []
        // 额度窗口：TOKENS_LIMIT（老套餐，仅百分比）与 CREDIT_LIMIT（新套餐，含次数绝对值）
        // unit 3 = 5 小时，unit 6 = 7 天；缺 unit 时按重置时间升序（先重置的为 5 小时）
        let quotaLimits = limits
            .filter {
                let type = $0["type"]?.string
                return type == "TOKENS_LIMIT" || type == "CREDIT_LIMIT"
            }
            .sorted { ($0["nextResetTime"]?.double ?? 0) < ($1["nextResetTime"]?.double ?? 0) }
        var fiveHourSlotUsed = false
        for limit in quotaLimits {
            let title: String?
            switch limit["unit"]?.int {
            case 3: title = "5 小时"
            case 6: title = "7 天"
            default: title = fiveHourSlotUsed ? "7 天" : "5 小时" // 老套餐缺 unit 字段
            }
            if title == "5 小时" { fiveHourSlotUsed = true }
            if let title {
                // CREDIT_LIMIT 返回绝对值（currentValue/usage），TOKENS_LIMIT 只有百分比
                let used = limit["currentValue"]?.int
                let total = limit["usage"]?.int
                var percent = limit["percentage"]?.double
                if percent == nil, let used, let total, total > 0 {
                    percent = min(Double(used) / Double(total) * 100, 100)
                }
                let text: String?
                if let used, let total {
                    text = "\(used)/\(total)"
                } else {
                    text = nil
                }
                windows.append(UsageWindow(
                    title: title,
                    usedPercent: percent,
                    usedText: text,
                    resetTime: limit["nextResetTime"]?.epochMsDate
                ))
            }
        }
        // 月度工具窗口（TIME_LIMIT）：次数绝对值
        if let monthly = limits.first(where: { $0["type"]?.string == "TIME_LIMIT" }) {
            let used = monthly["currentValue"]?.int
            let total = monthly["usage"]?.int
            windows.append(UsageWindow(
                title: "月度工具",
                usedPercent: monthly["percentage"]?.double,
                usedText: used != nil || total != nil ? "\(used ?? 0)/\(total ?? 0) 次" : nil,
                resetTime: monthly["nextResetTime"]?.epochMsDate
            ))
        }
        // 30 天累计消耗（model-usage 统计接口，免 Cookie）：
        // GLM 编程套餐无月度额度上限（按 5h/7d 滚动窗口计），
        // 但可统计区间累计 token 消耗与调用次数作为「总消耗量」参考。
        if let cumulative = await fetchGLMCumulative(key: config.cleanAPIKey) {
            windows.append(cumulative)
        }

        guard !windows.isEmpty else { throw APIClient.APIError.emptyResponse }
        return ProviderUsage(
            kind: .glm, displayName: config.name, state: .ok,
            currency: nil, totalBalance: nil, grantedBalance: nil,
            toppedUpBalance: nil, isAvailable: nil,
            windows: windows, fetchedAt: Date()
        )
    }

    /// GET /api/monitor/usage/model-usage?startTime&endTime（yyyy-MM-dd HH:mm:ss）
    /// 返回 totalUsage.totalTokensUsage / totalModelCallCount，失败静默忽略（不影响主窗口）。
    private static func fetchGLMCumulative(key: String) async -> UsageWindow? {
        guard let url = URL(string: "https://open.bigmodel.cn/api/monitor/usage/model-usage") else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let params = [
            URLQueryItem(name: "startTime", value: formatter.string(from: start)),
            URLQueryItem(name: "endTime", value: formatter.string(from: now)),
        ]
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = params
        guard let finalURL = components?.url else { return nil }
        return try? await APIClient.shared.get(
            finalURL, headers: ["Authorization": key, "Accept": "application/json"]
        )["data"]?["totalUsage"].flatMap { total in
            let tokens = total["totalTokensUsage"]?.int ?? 0
            let calls = total["totalModelCallCount"]?.int ?? 0
            guard tokens > 0 || calls > 0 else { return nil }
            return UsageWindow(
                title: "30 天累计",
                usedPercent: nil,
                usedText: "\(Self.formatTokenCount(tokens)) tokens · \(calls) 次",
                resetTime: nil
            )
        }
    }

    /// 大数中文格式化：55237346 → "5524万"
    static func formatTokenCount(_ value: Int) -> String {
        if value >= 100_000_000 {
            return String(format: "%.1f亿", Double(value) / 100_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.0f万", Double(value) / 10_000)
        }
        return "\(value)"
    }
}
