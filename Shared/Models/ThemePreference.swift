import SwiftUI

/// 界面主题偏好：主 App 窗口与小组件共用。
enum ThemePreference: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// nil 表示跟随系统，不强制
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension View {
    /// 按主题偏好强制明暗外观（跟随系统时不做任何修改）
    @ViewBuilder
    func themed(_ theme: ThemePreference) -> some View {
        if let scheme = theme.colorScheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}
