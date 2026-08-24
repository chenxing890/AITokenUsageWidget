import WidgetKit
import SwiftUI
import UserNotifications

@main
struct TokenUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenUsageWidget()
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let usages: [ProviderUsage]
    let theme: ThemePreference

    init(date: Date, usages: [ProviderUsage], theme: ThemePreference? = nil) {
        self.date = date
        self.usages = usages
        self.theme = theme ?? ConfigStore.shared.loadTheme()
    }
}

struct TokenUsageTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), usages: [
            .placeholder(kind: .deepseek),
            .placeholder(kind: .kimi),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        // 先用缓存快速上屏，避免快照时网络阻塞
        let cached = ConfigStore.shared.loadCachedUsages()
        completion(UsageEntry(date: Date(), usages: cached.isEmpty ? placeholder(in: context).usages : cached))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let configs = ConfigStore.shared.activeConfigs()
            let usages: [ProviderUsage]
            if configs.isEmpty {
                usages = []
            } else {
                usages = await UsageService.fetchAll(configs: configs)
                ConfigStore.shared.saveCachedUsages(usages)
                Self.sendUsageAlerts(usages)
            }
            let entry = UsageEntry(date: Date(), usages: usages)
            // 15 分钟后刷新（系统会按预算调度）
            let next = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// 用量达到阈值（主界面可配，默认 80%）发系统通知（每个「供应商-窗口」只通知一次，
    /// 回落到阈值 -10% 以下后重置，以便额度周期重置或再次冲高时能重新提醒）。
    private static func sendUsageAlerts(_ usages: [ProviderUsage]) {
        guard ConfigStore.shared.loadAlertsEnabled() else { return }
        let threshold = ConfigStore.shared.loadAlertThreshold()
        let resetBelow = threshold - 10
        var alerted = ConfigStore.shared.loadAlertedKeys()
        var changed = false
        for usage in usages where usage.state == .ok {
            for window in usage.windows {
                guard let percent = window.usedPercent else { continue }
                let key = "\(usage.kind.rawValue)-\(window.title)"
                if percent >= threshold {
                    guard !alerted.contains(key) else { continue }
                    alerted.insert(key)
                    changed = true
                    let content = UNMutableNotificationContent()
                    content.title = "\(usage.displayName) 用量告警"
                    content.body = "\(window.title)已使用 \(Int(percent.rounded()))%，达到告警阈值 \(Int(threshold))%。"
                    content.sound = .default
                    let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                } else if percent < resetBelow, alerted.contains(key) {
                    alerted.remove(key)
                    changed = true
                }
            }
        }
        if changed { ConfigStore.shared.saveAlertedKeys(alerted) }
    }
}

/// 小组件背景：按主题显式取色（containerBackground 的动态色不响应 colorScheme 覆盖）。
/// 颜色接近通知中心其他小组件：浅色近白、深色近系统深灰。
struct WidgetBackground: View {
    let theme: ThemePreference
    @Environment(\.colorScheme) private var systemScheme

    private var effective: ColorScheme { theme.colorScheme ?? systemScheme }

    var body: some View {
        if effective == .dark {
            Color(white: 0.13)
        } else {
            Color(white: 0.97)
        }
    }
}

struct TokenUsageWidget: Widget {
    let kind = "TokenUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenUsageTimelineProvider()) { entry in
            widgetContent(entry)
        }
        .configurationDisplayName("AI 模型用量")
        .description("显示 DeepSeek 余额与 Kimi / GLM 的 5 小时、7 天及总用量。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }

    @ViewBuilder
    private func widgetContent(_ entry: UsageEntry) -> some View {
        // 主题环境必须在背景之前注入，卡片与文字颜色才会随主题切换
        let content = TokenUsageWidgetEntryView(entry: entry).themed(entry.theme)
        if #available(macOS 14.0, *) {
            // containerBackground 的动态色由系统解析、不吃 colorScheme 覆盖，
            // 必须按主题显式给背景色
            content.containerBackground(for: .widget) {
                WidgetBackground(theme: entry.theme)
            }
        } else {
            // macOS 12/13：无 containerBackground API，背景由系统绘制（跟随系统外观）
            content
        }
    }
}
