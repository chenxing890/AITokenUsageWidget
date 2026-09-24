import SwiftUI

/// 供应商品牌图标（圆角渐变底 + 白色 SF Symbol），App 与 Widget 共用。
struct ProviderChip: View {
    let kind: ProviderKind
    var size: CGFloat = 20
    var iconSize: CGFloat = 10

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(
                        LinearGradient(colors: [kind.accentColor, kind.accentColor.opacity(0.62)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
    }
}

/// 供应商卡片（Widget 与 App 预览共用）。
/// - compact：medium 尺寸两列时的紧凑度
/// - dense：medium 三列时的极简模式——窗口渲染为单行文本（无进度条），最大化利用宽度
struct ProviderCardView: View {
    let usage: ProviderUsage
    var compact = false
    var dense = false

    var body: some View {
        HStack(spacing: dense ? 4 : (compact ? 6 : 8)) {
            // 品牌色条
            Capsule()
                .fill(
                    LinearGradient(colors: [usage.kind.accentColor, usage.kind.accentColor.opacity(0.45)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: dense ? 2 : 3)

            VStack(alignment: .leading, spacing: dense ? 3 : (compact ? 5 : 7)) {
                header
                switch usage.state {
                case .ok:
                    if usage.kind.showsBalance {
                        balanceBody
                    } else {
                        windowsBody
                    }
                case .missingKey:
                    hint("未配置 API Key", color: .secondary)
                case .error(let message):
                    hint(message, color: .red)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(dense ? 5 : (compact ? 7 : 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: dense ? 9 : 12, style: .continuous)
                // 不用 .fill.quaternary（macOS 14+），用主色低透明度兼容 macOS 12
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: dense ? 3 : 5) {
            ProviderChip(kind: usage.kind,
                         size: dense ? 13 : (compact ? 16 : 19),
                         iconSize: dense ? 6 : (compact ? 8 : 10))
            Text(usage.displayName)
                .font(dense ? .system(size: 9, weight: .semibold) : .caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if !dense {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var statusColor: Color {
        switch usage.state {
        case .ok:
            if usage.kind.showsBalance, usage.isAvailable == false { return .red }
            return .green
        case .missingKey: return .gray
        case .error: return .red
        }
    }

    private func hint(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .lineLimit(dense ? 3 : 2)
            .minimumScaleFactor(0.8)
    }

    // MARK: - DeepSeek 余额

    private var balanceBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(usage.currencySymbol)
                    .font(dense ? .system(size: 8) : (compact ? .caption : .callout))
                    .foregroundStyle(.secondary)
                Text(usage.totalBalance.map { String(format: "%.2f", $0) } ?? "--")
                    .font(.system(size: dense ? 15 : (compact ? 21 : 26),
                                  weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if !dense, !compact {
                Text("赠送 \(amountText(usage.grantedBalance)) · 充值 \(amountText(usage.toppedUpBalance))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func amountText(_ value: Double?) -> String {
        "\(usage.currencySymbol)\(value.map { String(format: "%.2f", $0) } ?? "--")"
    }

    // MARK: - Kimi / GLM 用量窗口

    private var windowsBody: some View {
        VStack(alignment: .leading, spacing: dense ? 3 : (compact ? 5 : 7)) {
            ForEach(usage.windows.prefix(dense ? 3 : usage.windows.count)) { window in
                if dense {
                    denseWindowRow(window)
                } else {
                    windowRow(window)
                }
            }
        }
    }

    /// 极简单行：标题 + 百分比（或累计文本），下挂超细迷你进度条（含健康配额线）
    private func denseWindowRow(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(window.shortTitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 1)
                if let percent = window.usedPercent {
                    Text("\(Int(percent.rounded()))%")
                        .monospacedDigit()
                        .fontWeight(.medium)
                } else if let text = window.usedText {
                    Text(text)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            if window.usedPercent != nil {
                miniProgressBar(percent: window.usedPercent ?? 0,
                                healthLine: window.healthLinePercent)
            }
        }
        .font(.system(size: 9))
    }

    /// dense 模式迷你进度条：高度 2pt，不挤占布局
    private func miniProgressBar(percent: Double, healthLine: Double?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(levelColor(percent))
                    .frame(width: max(2, geo.size.width * min(max(percent, 0) / 100, 1)))
                if let healthLine {
                    Capsule()
                        .fill(Color.gray.opacity(0.75))
                        .frame(width: 1.5, height: 2)
                        .offset(x: max(0, geo.size.width * healthLine / 100 - 0.75))
                }
            }
        }
        .frame(height: 2)
    }

    private func windowRow(_ window: UsageWindow) -> some View {
        // 无百分比的窗口（如「30 天累计」）渲染为单行文本，不画进度条
        if window.usedPercent == nil {
            return AnyView(HStack(spacing: 4) {
                Text(window.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(window.usedText ?? "--")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            })
        }
        return AnyView(VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(window.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if !compact, let text = window.usedText {
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let percent = window.usedPercent {
                    Text("\(Int(percent.rounded()))%")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                }
                if let reset = window.resetTime {
                    HStack(spacing: 2) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 8))
                        Text(reset, style: .timer)
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
            progressBar(percent: window.usedPercent ?? 0, healthLine: window.healthLinePercent)
        })
    }

    private func progressBar(percent: Double, healthLine: Double? = nil) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(
                        LinearGradient(colors: [levelColor(percent).opacity(0.7), levelColor(percent)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(3, geo.size.width * min(max(percent, 0) / 100, 1)))
                if let healthLine {
                    // 健康配额线：随时间推进的刻度线，用量超过它即超前消耗
                    Capsule()
                        .fill(Color.gray.opacity(0.75))
                        .frame(width: 1.5, height: 4)
                        .offset(x: max(0, geo.size.width * healthLine / 100 - 0.75))
                }
            }
        }
        .frame(height: 4)
    }

    private func levelColor(_ percent: Double) -> Color {
        switch percent {
        case 80...: return .red
        case 50..<80: return .orange
        default: return .green
        }
    }
}

/// 窗口的极简标题（dense 三列布局用）
extension UsageWindow {
    var shortTitle: String {
        switch title {
        case "5 小时": return "5h"
        case "7 天": return "7d"
        case "月度工具": return "工具"
        case "本月总额", "30 天累计": return "30d"
        default: return title
        }
    }
}

/// 7 天窗口的「健康配额线」：7 天额度按天均摊，健康节奏是每天用掉总额的 1/7。
/// 线按「当天目标配额」定位：窗口起点 = 重置时间 − 7 天，已完整过整天数 d = floor(已过天数)，
/// 位置 = d/7（第 1 天 14.28%、第 2 天 28.57% … 第 6 天 85.71%）。最后一天（d=6）封顶
/// 85.71%，不画到 100%（进度条末端无意义）；第 0 天（刚重置）不画线。当前用量超过该线，
/// 即意味着超前消耗、挤占后续份额。
extension UsageWindow {
    private static let dayInterval: TimeInterval = 24 * 3600

    var healthLinePercent: Double? {
        guard title == "7 天", let reset = resetTime else { return nil }
        let start = reset.addingTimeInterval(-7 * Self.dayInterval)
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return nil }
        var d = Int(elapsed / Self.dayInterval) // 已完整过整天数
        guard d >= 1 else { return nil }        // 第 0 天：起点，不画线
        d = min(d, 6)                            // 最后一天封顶第 6 天（85.71%）
        return Double(d) / 7.0 * 100.0
    }
}
