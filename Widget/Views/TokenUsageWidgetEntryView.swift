import SwiftUI
import WidgetKit

/// Widget 入口视图：medium 自适应列数（≤2 紧凑卡片，3 个 dense 三列）；large 纵向列表 + 更新时间。
struct TokenUsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: UsageEntry

    var body: some View {
        if entry.usages.isEmpty {
            emptyView
        } else if family == .systemLarge {
            largeView
        } else {
            mediumView
        }
    }

    // MARK: - Medium：自适应列数

    private var mediumView: some View {
        let dense = entry.usages.count > 2
        return HStack(spacing: dense ? 6 : 8) {
            ForEach(entry.usages.prefix(3)) { usage in
                ProviderCardView(usage: usage, compact: !dense, dense: dense)
            }
        }
        .padding(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Large：纵向列表

    private var largeView: some View {
        VStack(spacing: 8) {
            ForEach(entry.usages.prefix(4)) { usage in
                ProviderCardView(usage: usage)
            }
            if let updated = entry.usages.map(\.fetchedAt).min() {
                HStack(spacing: 3) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 8))
                    Text("更新于 ")
                    Text(updated, style: .offset)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 未配置引导

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(
                    LinearGradient(colors: [.indigo, .cyan],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("打开「AI 用量监控」App\n启用并配置供应商")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
