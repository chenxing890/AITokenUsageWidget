import Foundation

/// 单个供应商的配置（App 配置界面编辑，经 App Group 共享给 Widget）。
/// 同 kind 允许存在多个实例（如两个 Kimi Code 账号），通过 UUID id 区分。
struct ProviderConfig: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: ProviderKind
    var isEnabled: Bool = false
    var apiKey: String = ""
    /// 自定义接口根地址，留空使用 kind.defaultBaseURL
    var baseURLOverride: String = ""
    /// 自定义显示名，留空使用 kind.displayName
    var customName: String = ""
    /// 附加凭证：Kimi 的 kimi-auth Cookie（可选，用于查询月度总用量）
    var extraToken: String = ""
    /// 是否在通知中心小组件中显示（最多同时勾选 3 个，由 UI 层限制）
    var showInWidget: Bool = false

    var hasKey: Bool { !cleanAPIKey.isEmpty }
    /// 去除首尾空白/换行，并剥离误粘贴的 "Bearer " 前缀
    var cleanAPIKey: String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("Bearer ") ? String(trimmed.dropFirst(7)) : trimmed
    }
    var hasExtraToken: Bool { !extraToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var name: String {
        let trimmed = customName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? kind.displayName : trimmed
    }

    init(kind: ProviderKind) {
        self.kind = kind
    }

    // 自定义解码：showInWidget 等后增字段缺失时使用默认值，保证旧 JSON 可升级
    private enum CodingKeys: String, CodingKey {
        case id, kind, isEnabled, apiKey, baseURLOverride, customName, extraToken, showInWidget
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = try c.decode(ProviderKind.self, forKey: .kind)
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        apiKey = (try? c.decodeIfPresent(String.self, forKey: .apiKey)) ?? ""
        baseURLOverride = (try? c.decodeIfPresent(String.self, forKey: .baseURLOverride)) ?? ""
        customName = (try? c.decodeIfPresent(String.self, forKey: .customName)) ?? ""
        extraToken = (try? c.decodeIfPresent(String.self, forKey: .extraToken)) ?? ""
        showInWidget = (try? c.decodeIfPresent(Bool.self, forKey: .showInWidget)) ?? false
    }

    /// 拼接接口地址：内置 base + path（path 以 "/" 开头）
    func apiURL(path: String) -> URL? {
        var base = kind.defaultBaseURL
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)
    }
}
