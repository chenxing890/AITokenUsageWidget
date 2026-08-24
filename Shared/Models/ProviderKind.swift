import Foundation
import SwiftUI

/// 供应商种类。新增模型供应商时在此扩展 case 并补齐各属性。
enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case deepseek
    case kimi
    case glm

    var id: String { rawValue }

    /// 默认显示名（用户可在配置中自定义）
    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .kimi: return "Kimi Code"
        case .glm: return "GLM Coding"
        }
    }

    /// 副标题（侧边栏 / 详情页一行说明）
    var subtitle: String {
        switch self {
        case .deepseek: return "账户余额监控"
        case .kimi: return "5 小时 · 7 天 · 月度额度"
        case .glm: return "5 小时 · 7 天 · 月度工具"
        }
    }

    /// 默认接口根地址（自定义地址留空时使用）
    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .kimi: return "https://api.kimi.com/coding/v1"
        case .glm: return "https://open.bigmodel.cn"
        }
    }

    /// SF Symbol 图标
    var systemImage: String {
        switch self {
        case .deepseek: return "drop.fill"
        case .kimi: return "moon.stars.fill"
        case .glm: return "sparkles"
        }
    }

    /// 品牌色（图标底、进度条、强调按钮）
    var accentColor: Color {
        switch self {
        case .deepseek: return Color(red: 0.23, green: 0.51, blue: 0.96)
        case .kimi: return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .glm: return Color(red: 0.02, green: 0.62, blue: 0.53)
        }
    }

    /// API Key 格式提示
    var apiKeyHelp: String {
        switch self {
        case .deepseek: return "sk-xxx"
        case .kimi: return "sk-kimi-xxx"
        case .glm: return "与调用 /api/paas/v4 同一把"
        }
    }

    /// 控制台地址（配置界面「打开控制台」按钮）
    var consoleURL: String {
        switch self {
        case .deepseek: return "https://platform.deepseek.com/api_keys"
        case .kimi: return "https://www.kimi.com/code/console"
        case .glm: return "https://open.bigmodel.cn/apikey"
        }
    }

    /// 是否支持附加凭证（当前仅 Kimi：kimi-auth Cookie 用于月度总用量）
    var supportsCookie: Bool { self == .kimi }

    /// 是否为余额型供应商（卡片按余额渲染，而非用量窗口）
    var showsBalance: Bool { self == .deepseek }
}
