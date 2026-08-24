import Foundation

/// 一次用量查询的结果快照。DeepSeek 走余额字段，Kimi / GLM 走窗口数组。
struct ProviderUsage: Codable, Equatable, Identifiable {
    enum State: Codable, Equatable {
        case ok
        case missingKey
        case error(String)

        private enum CodingKeys: String, CodingKey { case ok, missingKey, error }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let msg = try container.decodeIfPresent(String.self, forKey: .error) {
                self = .error(msg)
            } else if container.contains(.missingKey) {
                self = .missingKey
            } else {
                self = .ok
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .ok: break
            case .missingKey: try container.encodeNil(forKey: .missingKey)
            case .error(let msg): try container.encode(msg, forKey: .error)
            }
        }
    }

    var id: String { "\(kind.rawValue)|\(displayName)" }

    let kind: ProviderKind
    let displayName: String
    let state: State

    // MARK: DeepSeek 余额（showsBalance == true 时使用）
    let currency: String?
    let totalBalance: Double?
    let grantedBalance: Double?
    let toppedUpBalance: Double?
    let isAvailable: Bool?

    // MARK: Kimi / GLM 用量窗口
    let windows: [UsageWindow]

    let fetchedAt: Date

    var currencySymbol: String { currency == "USD" ? "$" : "¥" }
}

/// 一个用量窗口（如「5 小时」「7 天」「本月总额」）。
struct UsageWindow: Codable, Equatable, Identifiable {
    var id: String { title }

    let title: String
    /// 已用百分比（0–100）
    let usedPercent: Double?
    /// 用量文本（GLM 月度工具等有绝对值的场景，如 "126/1000 次"）
    let usedText: String?
    /// 重置时间
    let resetTime: Date?
}

// MARK: - 占位数据（Widget 预览 / 快照回退）

extension ProviderUsage {
    static func placeholder(kind: ProviderKind) -> ProviderUsage {
        switch kind {
        case .deepseek:
            return ProviderUsage(
                kind: .deepseek, displayName: kind.displayName, state: .ok,
                currency: "CNY", totalBalance: 88.50,
                grantedBalance: 10.00, toppedUpBalance: 78.50, isAvailable: true,
                windows: [], fetchedAt: Date()
            )
        case .kimi:
            return ProviderUsage(
                kind: .kimi, displayName: kind.displayName, state: .ok,
                currency: nil, totalBalance: nil, grantedBalance: nil,
                toppedUpBalance: nil, isAvailable: nil,
                windows: [
                    UsageWindow(title: "5 小时", usedPercent: 42, usedText: nil,
                                resetTime: Date().addingTimeInterval(2 * 3600)),
                    UsageWindow(title: "7 天", usedPercent: 68, usedText: nil,
                                resetTime: Date().addingTimeInterval(3 * 86400)),
                    UsageWindow(title: "本月总额", usedPercent: 35, usedText: nil,
                                resetTime: Date().addingTimeInterval(12 * 86400)),
                ], fetchedAt: Date()
            )
        case .glm:
            return ProviderUsage(
                kind: .glm, displayName: kind.displayName, state: .ok,
                currency: nil, totalBalance: nil, grantedBalance: nil,
                toppedUpBalance: nil, isAvailable: nil,
                windows: [
                    UsageWindow(title: "5 小时", usedPercent: 21, usedText: nil,
                                resetTime: Date().addingTimeInterval(3600)),
                    UsageWindow(title: "7 天", usedPercent: 55, usedText: nil,
                                resetTime: Date().addingTimeInterval(4 * 86400)),
                    UsageWindow(title: "月度工具", usedPercent: 12, usedText: "126/1000 次",
                                resetTime: Date().addingTimeInterval(18 * 86400)),
                ], fetchedAt: Date()
            )
        }
    }
}
