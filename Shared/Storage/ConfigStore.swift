import Foundation
import Security

/// App Group 共享存储：配置 + 用量缓存。
/// - 正式签名（签名内嵌 App Groups entitlement）：走 App Group UserDefaults。
/// - 本地 ad-hoc 运行（macOS 无描述文件时 codesign 会剥离该 entitlement）：
///   自动降级为「Widget 扩展容器内的共享 JSON 文件」。主 App 以非沙盒运行可直接
///   读写扩展容器路径，扩展自身可访问自己容器，两端指向同一文件，共享依然成立。
/// 路径选择必须确定性：用 SecTask 读取本进程签名内的 entitlement 判断，
/// 不依赖 containerURL / UserDefaults 的容错行为（它们在无授权时可能「假成功」，
/// 导致 Widget 读到自己容器内的空 plist）。
final class ConfigStore {
    static let shared = ConfigStore()

    static let appGroupID = "group.com.chenxing.tokenusage"
    private static let widgetBundleID = "com.chenxing.tokenusage.app.widget"
    private static let configsKey = "providerConfigs"
    private static let cacheKey = "cachedUsages"
    private static let alertedKey = "alertedUsageKeys"

    /// 单文件负载（降级文件存储用）。
    /// 自定义解码：所有字段容错（try? decodeIfPresent），任何单字段缺失或结构
    /// 变化都不会导致整个文件解码失败——否则空负载会被当成「无配置」覆盖写回，
    /// 清空用户已有配置。
    private struct Payload: Codable {
        var configs: [ProviderConfig] = []
        var cachedUsages: [ProviderUsage] = []
        var theme: ThemePreference?
        var alertedKeys: [String] = []
        var alertsEnabled: Bool?
        var alertThreshold: Double?

        init() {}

        init(configs: [ProviderConfig], cachedUsages: [ProviderUsage]) {
            self.configs = configs
            self.cachedUsages = cachedUsages
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            configs = (try? container.decodeIfPresent([ProviderConfig].self, forKey: .configs)) ?? []
            cachedUsages = (try? container.decodeIfPresent([ProviderUsage].self, forKey: .cachedUsages)) ?? []
            theme = try? container.decodeIfPresent(ThemePreference.self, forKey: .theme)
            alertedKeys = (try? container.decodeIfPresent([String].self, forKey: .alertedKeys)) ?? []
            alertsEnabled = try? container.decodeIfPresent(Bool.self, forKey: .alertsEnabled)
            alertThreshold = try? container.decodeIfPresent(Double.self, forKey: .alertThreshold)
        }
    }

    private let groupDefaults: UserDefaults?
    private let fileURL: URL?

    init() {
        if Self.hasAppGroupEntitlement(), let defaults = UserDefaults(suiteName: Self.appGroupID) {
            groupDefaults = defaults
            fileURL = nil
        } else {
            groupDefaults = nil
            fileURL = Self.fallbackFileURL()
        }
    }

    /// 读取本进程签名内嵌的 application-groups entitlement。
    /// ad-hoc 本地签名的 entitlement 会被系统剥离，SecTask 查不到 → 返回 false。
    private static func hasAppGroupEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(
            task, "com.apple.security.application-groups" as CFString, nil
        ) as? [String]
        return value?.contains(appGroupID) == true
    }

    /// 降级共享文件：Widget 扩展沙盒容器内的固定路径
    /// （扩展进程：自身容器 App Support；主 App 进程：显式指向扩展容器的绝对路径）
    private static func fallbackFileURL() -> URL? {
        let dir: URL
        if Bundle.main.bundleIdentifier == widgetBundleID {
            // Widget 扩展：沙盒会把 App Support 映射到自身容器
            if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                dir = support.appendingPathComponent("AITokenUsageWidget", isDirectory: true)
            } else {
                return nil
            }
        } else {
            // 主 App（本地非沙盒运行）：直接写扩展容器
            dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Library/Application Support/AITokenUsageWidget", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shared.json")
    }

    // MARK: - 读写底层

    private func loadPayload() -> Payload {
        if let defaults = groupDefaults {
            let configs = defaults.data(forKey: Self.configsKey)
                .flatMap { try? JSONDecoder().decode([ProviderConfig].self, from: $0) } ?? []
            let cached = defaults.data(forKey: Self.cacheKey)
                .flatMap { try? JSONDecoder().decode([ProviderUsage].self, from: $0) } ?? []
            return Payload(configs: configs, cachedUsages: cached)
        }
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else {
            // 文件不存在：首次运行，返回空负载
            return Payload()
        }
        if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            return payload
        }
        // 解码失败（版本不兼容/文件损坏）：原文件改名保留，绝不静默覆盖用户数据。
        // 保留的文件可手动恢复或排查。
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("shared.corrupt-\(formatter.string(from: Date())).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        return Payload()
    }

    private func savePayload(_ payload: Payload) {
        if let defaults = groupDefaults {
            defaults.set(try? JSONEncoder().encode(payload.configs), forKey: Self.configsKey)
            defaults.set(try? JSONEncoder().encode(payload.cachedUsages), forKey: Self.cacheKey)
        } else if let url = fileURL, let data = try? JSONEncoder().encode(payload) {
            // 写入前先把现有文件备份为 shared.json.bak，任何误写都可回滚一份
            if FileManager.default.fileExists(atPath: url.path) {
                let backup = url.deletingPathExtension().appendingPathExtension("json.bak")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: url, to: backup)
            }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - 供应商配置

    /// 读取全部配置；首次调用时生成默认配置，并自动补齐后续版本新增的供应商。
    func loadConfigs() -> [ProviderConfig] {
        let payload = loadPayload()
        if payload.configs.isEmpty {
            let fresh = ProviderKind.allCases.map { ProviderConfig(kind: $0) }
            var next = payload
            next.configs = fresh
            savePayload(next)
            return fresh
        }
        let existing = Set(payload.configs.map(\.kind))
        let missing = ProviderKind.allCases.filter { !existing.contains($0) }
        if !missing.isEmpty {
            var next = payload
            next.configs += missing.map { ProviderConfig(kind: $0) }
            savePayload(next)
        }
        return payload.configs
    }

    func saveConfigs(_ configs: [ProviderConfig]) {
        var payload = loadPayload()
        payload.configs = configs
        savePayload(payload)
    }

    /// 已启用的供应商
    func activeConfigs() -> [ProviderConfig] {
        loadConfigs().filter(\.isEnabled)
    }

    // MARK: - 主题偏好（App 窗口与小组件共用）

    func loadTheme() -> ThemePreference {
        if let defaults = groupDefaults {
            return ThemePreference(rawValue: defaults.string(forKey: "themePreference") ?? "") ?? .system
        }
        return loadPayload().theme ?? .system
    }

    func saveTheme(_ theme: ThemePreference) {
        if let defaults = groupDefaults {
            defaults.set(theme.rawValue, forKey: "themePreference")
        } else {
            var payload = loadPayload()
            payload.theme = theme
            savePayload(payload)
        }
    }

    // MARK: - 用量告警开关（默认开启）

    func loadAlertsEnabled() -> Bool {
        if let defaults = groupDefaults {
            return defaults.object(forKey: "alertsEnabled") as? Bool ?? true
        }
        return loadPayload().alertsEnabled ?? true
    }

    func saveAlertsEnabled(_ enabled: Bool) {
        if let defaults = groupDefaults {
            defaults.set(enabled, forKey: "alertsEnabled")
        } else {
            var payload = loadPayload()
            payload.alertsEnabled = enabled
            savePayload(payload)
        }
    }

    /// 可选的告警阈值（百分比）
    static let alertThresholdOptions: [Double] = [50, 60, 70, 80, 90, 95]

    /// 告警阈值（百分比，默认 80）
    func loadAlertThreshold() -> Double {
        if let defaults = groupDefaults {
            let value = defaults.double(forKey: "alertThreshold")
            return value > 0 ? value : 80
        }
        return loadPayload().alertThreshold ?? 80
    }

    func saveAlertThreshold(_ threshold: Double) {
        if let defaults = groupDefaults {
            defaults.set(threshold, forKey: "alertThreshold")
        } else {
            var payload = loadPayload()
            payload.alertThreshold = threshold
            savePayload(payload)
        }
    }

    // MARK: - 用量告警记录（已通知过的「供应商-窗口」，回落后自动重置）

    func loadAlertedKeys() -> Set<String> {
        if let defaults = groupDefaults {
            return Set(defaults.stringArray(forKey: Self.alertedKey) ?? [])
        }
        return Set(loadPayload().alertedKeys)
    }

    func saveAlertedKeys(_ keys: Set<String>) {
        if let defaults = groupDefaults {
            defaults.set(Array(keys), forKey: Self.alertedKey)
        } else {
            var payload = loadPayload()
            payload.alertedKeys = Array(keys)
            savePayload(payload)
        }
    }

    // MARK: - 用量缓存（Widget 刷新失败时回退显示）

    func saveCachedUsages(_ usages: [ProviderUsage]) {
        var payload = loadPayload()
        payload.cachedUsages = usages
        savePayload(payload)
    }

    func loadCachedUsages() -> [ProviderUsage] {
        loadPayload().cachedUsages
    }
}
