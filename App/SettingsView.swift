import SwiftUI
import WidgetKit

/// 主 App 设置界面：左侧供应商列表 + 右侧配置详情（含小组件实时预览）。
struct SettingsView: View {
    @State private var configs: [ProviderConfig] = []
    @State private var selectedID: UUID?
    @State private var testResults: [UUID: ProviderUsage] = [:]
    @State private var testingIDs: Set<UUID> = []
    @State private var savedToast = false
    @State private var theme: ThemePreference = .system
    @State private var alertsEnabled = true
    @State private var alertThreshold: Double = 80

    var body: some View {
        rootContent
        .navigationTitle("AI 模型用量")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: refreshWidget) {
                    Label("刷新小组件", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .help("配置已自动保存，此按钮让小组件立即重新拉取数据")
            }
        }
        .overlay(alignment: .bottom) { toast }
        .preferredColorScheme(theme.colorScheme)
        .onAppear {
            if configs.isEmpty { configs = ConfigStore.shared.loadConfigs() }
            if selectedID == nil { selectedID = configs.first?.id }
            theme = ConfigStore.shared.loadTheme()
            alertsEnabled = ConfigStore.shared.loadAlertsEnabled()
            alertThreshold = ConfigStore.shared.loadAlertThreshold()
        }
        // 配置改动即时落盘，无需手动保存
        .onChange(of: configs) { newConfigs in
            ConfigStore.shared.saveConfigs(newConfigs)
        }
        // 主题改动即时落盘并刷新小组件
        .onChange(of: theme) { newTheme in
            ConfigStore.shared.saveTheme(newTheme)
            WidgetCenter.shared.reloadAllTimelines()
        }
        // 告警开关即时落盘
        .onChange(of: alertsEnabled) { enabled in
            ConfigStore.shared.saveAlertsEnabled(enabled)
        }
        // 告警阈值即时落盘（清空已通知记录，按新阈值重新判定）
        .onChange(of: alertThreshold) { threshold in
            ConfigStore.shared.saveAlertThreshold(threshold)
            ConfigStore.shared.saveAlertedKeys([])
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private var selectedBinding: Binding<ProviderConfig>? {
        guard let id = selectedID,
              let index = configs.firstIndex(where: { $0.id == id }) else { return nil }
        return $configs[index]
    }

    // MARK: - 根布局（macOS 13+ 用原生分栏，macOS 12 降级为 HStack）

    @ViewBuilder
    private var rootContent: some View {
        if #available(macOS 13.0, *) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
            } detail: {
                detail
            }
        } else {
            HStack(spacing: 0) {
                legacySidebar
                    .frame(width: 240)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let config = selectedBinding {
            ProviderDetailColumn(config: config,
                                 testResults: $testResults,
                                 testingIDs: $testingIDs)
        } else {
            Text("从左侧选择一个供应商")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        // 不用 safeAreaInset（macOS 13+），VStack 底部放状态栏兼容 macOS 12
        VStack(spacing: 0) {
            List(selection: $selectedID) {
            Section("供应商") {
                ForEach(configs) { config in
                    SidebarRow(config: config)
                        .tag(config.id)
                }
            }
            Section("外观") {
                Picker("主题", selection: $theme) {
                    ForEach(ThemePreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("同时作用于主界面与通知中心小组件")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Section("通知") {
                Toggle("用量超阈值时通知", isOn: $alertsEnabled)
                    .font(.callout)
                Picker("通知阈值", selection: $alertThreshold) {
                    ForEach(ConfigStore.alertThresholdOptions, id: \.self) { option in
                        Text("\(Int(option))%").tag(option)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!alertsEnabled)
                Text("任一额度窗口用量达到阈值时发送系统通知")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
            .listStyle(.sidebar)
            Divider()
            Text("\(configs.filter(\.isEnabled).count)/\(configs.count) 已启用")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.regularMaterial)
        }
    }

    // MARK: - macOS 12 专用侧边栏

    /// macOS 12 降级侧边栏：不用 List（其 sidebar 材质在浅色主题下偏暗、
    /// 与详情区背景不一致），改用 ScrollView + 显式窗口背景色。
    private var legacySidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    legacySection("供应商") {
                        ForEach(configs) { config in
                            Button {
                                selectedID = config.id
                            } label: {
                                SidebarRow(config: config)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(selectedID == config.id
                                                  ? Color.accentColor.opacity(0.18)
                                                  : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    legacySection("外观") {
                        Picker("主题", selection: $theme) {
                            ForEach(ThemePreference.allCases) { preference in
                                Text(preference.label).tag(preference)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text("同时作用于主界面与通知中心小组件")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    legacySection("通知") {
                        Toggle("用量超阈值时通知", isOn: $alertsEnabled)
                            .font(.callout)
                        Picker("通知阈值", selection: $alertThreshold) {
                            ForEach(ConfigStore.alertThresholdOptions, id: \.self) { option in
                                Text("\(Int(option))%").tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(!alertsEnabled)
                        Text("任一额度窗口用量达到阈值时发送系统通知")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(14)
            }
            Divider()
            sidebarFooter
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func legacySection<Content: View>(_ title: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var sidebarFooter: some View {
        Text("\(configs.filter(\.isEnabled).count)/\(configs.count) 已启用")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.regularMaterial)
    }

    // MARK: - 保存提示

    @ViewBuilder
    private var toast: some View {
        if savedToast {
            Label("小组件已刷新", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.green.opacity(0.35)))
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func refreshWidget() {
        WidgetCenter.shared.reloadAllTimelines()
        withAnimation { savedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { savedToast = false }
        }
    }
}

// MARK: - 侧边栏行

private struct SidebarRow: View {
    let config: ProviderConfig

    var body: some View {
        HStack(spacing: 10) {
            ProviderChip(kind: config.kind, size: 28, iconSize: 13)
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(config.isEnabled ? config.kind.subtitle : "未启用")
                    .font(.caption2)
                    .foregroundStyle(config.isEnabled ? .secondary : .tertiary)
            }
            Spacer(minLength: 0)
            if config.isEnabled {
                Circle().fill(.green).frame(width: 7, height: 7)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 详情列

private struct ProviderDetailColumn: View {
    @Binding var config: ProviderConfig
    @Binding var testResults: [UUID: ProviderUsage]
    @Binding var testingIDs: Set<UUID>

    /// 已配置 Key 时自动拉取的实际用量（用于预览，无需手动点测试）
    @State private var liveUsage: ProviderUsage?

    private var kind: ProviderKind { config.kind }
    private var isTesting: Bool { testingIDs.contains(config.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if config.isEnabled {
                    apiSection
                    testSection
                } else {
                    disabledHint
                }
                previewSection
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 配置了 API Key 时自动拉取实际用量用于预览；Key 变化/清空时重新拉取或重置
        .task(id: config.cleanAPIKey) {
            guard config.hasKey else {
                liveUsage = nil
                return
            }
            liveUsage = await UsageService.fetch(config: config)
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 14) {
            ProviderChip(kind: kind, size: 46, iconSize: 21)
            VStack(alignment: .leading, spacing: 3) {
                Text(config.name)
                    .font(.title2.weight(.bold))
                Text(kind.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("启用", isOn: $config.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("启用后卡片会显示在通知中心小组件中")
        }
    }

    // MARK: 接口配置

    private var apiSection: some View {
        GroupCard(title: "接口配置", icon: "server.rack") {
            Text("接口地址已内置：\(kind.defaultBaseURL)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Field(label: "API Key（\(kind.apiKeyHelp)）") {
                SecureField("", text: $config.apiKey)
                    .textFieldStyle(.roundedBorder)
            }
            Field(label: "显示名称（留空使用 \(kind.displayName)）") {
                TextField("", text: $config.customName)
                    .textFieldStyle(.roundedBorder)
            }
            if kind.supportsCookie {
                Field(label: "kimi-auth Cookie（可选 · 用于月度总用量）") {
                    SecureField("", text: $config.extraToken)
                        .textFieldStyle(.roundedBorder)
                }
                Text("获取：浏览器登录 kimi.com → 开发者工具 → Application → Cookies → 复制 kimi-auth 的值。非官方接口，可能变动。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 连接测试

    private var testSection: some View {
        GroupCard(title: "连接测试", icon: "antenna.radiowaves.left.and.right") {
            HStack {
                Button(action: test) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("测试连接")
                    }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(kind.accentColor)
                .disabled(!config.hasKey || isTesting)

                Spacer()
                Link("打开控制台", destination: URL(string: kind.consoleURL)!)
                    .font(.callout)
            }
            if let usage = testResults[config.id] {
                resultView(usage)
            }
        }
    }

    @ViewBuilder
    private func resultView(_ usage: ProviderUsage) -> some View {
        switch usage.state {
        case .ok:
            if usage.kind.showsBalance {
                Label("连接成功：余额 \(usage.currencySymbol)\(usage.totalBalance.map { String(format: "%.2f", $0) } ?? "--")",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("连接成功：\(usage.windows.map { "\($0.title) \($0.usedPercent.map { String(format: "%.0f", $0) } ?? "--")%" }.joined(separator: " · "))",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .missingKey:
            Label("请先填写 API Key", systemImage: "key.slash")
                .foregroundStyle(.orange)
        case .error(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: 未启用提示

    private var disabledHint: some View {
        GroupCard(title: "未启用", icon: "info.circle") {
            Text("打开右上角开关启用 \(kind.displayName)。配置并保存后，对应卡片会自动出现在通知中心小组件中。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 小组件预览

    private var previewSection: some View {
        GroupCard(title: "小组件预览", icon: "rectangle.on.rectangle") {
            ProviderCardView(usage: previewUsage)
                .frame(height: 132)
                .overlay(alignment: .topTrailing) {
                    if isSimulated {
                        Text("模拟")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange))
                            .padding(6)
                    }
                }
            Text(isSimulated
                 ? "模拟数据 · 配置 API Key 后自动显示实际用量"
                 : "实际用量 · 更新于 \(previewUsage.fetchedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// 预览数据：手动测试结果 > 自动拉取的实际用量 > 模拟占位数据
    private var previewUsage: ProviderUsage {
        testResults[config.id] ?? liveUsage ?? .placeholder(kind: kind)
    }

    private var isSimulated: Bool {
        testResults[config.id] == nil && liveUsage == nil
    }

    private func test() {
        testingIDs.insert(config.id)
        Task {
            let usage = await UsageService.fetch(config: config)
            await MainActor.run {
                testResults[config.id] = usage
                testingIDs.remove(config.id)
            }
        }
    }
}

// MARK: - 复用小组件

/// 分组卡片容器
private struct GroupCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

/// 字段标签 + 输入控件
private struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}
