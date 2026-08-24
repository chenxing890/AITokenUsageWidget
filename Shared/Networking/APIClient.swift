import Foundation

/// 极简 HTTP 客户端（App 与 Widget 共用）。
struct APIClient {
    static let shared = APIClient()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    enum APIError: LocalizedError {
        case invalidURL
        case http(Int)
        case emptyResponse
        case message(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "接口地址无效"
            case .http(let code):
                switch code {
                case 401, 403: return "认证失败（HTTP \(code)）：请检查 API Key 是否正确"
                case 429: return "请求过于频繁（HTTP 429），请稍后重试"
                default: return "请求失败（HTTP \(code)）"
                }
            case .emptyResponse: return "服务器返回为空"
            case .message(let msg): return msg
            }
        }
    }

    // MARK: - 请求

    func get(_ url: URL, headers: [String: String] = [:]) async throws -> JSONValue {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await send(request)
    }

    func post(_ url: URL, headers: [String: String] = [:], body: Data? = nil) async throws -> JSONValue {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = body
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return try JSONValue(data: data)
    }

    /// 把底层错误转成用户可读的中文提示
    static func friendlyMessage(for error: Error) -> String {
        if let api = error as? APIError { return api.localizedDescription }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "请求超时，请稍后重试"
            case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost:
                return "网络连接失败，请检查网络"
            default: break
            }
        }
        if error is DecodingError { return "响应解析失败，接口格式可能已变更" }
        return "请求失败：\(error.localizedDescription)"
    }
}

// MARK: - 松散 JSON 辅助

/// 弱类型 JSON 值：供应商接口字段名 / 类型不统一（数字可能返回字符串），统一在此兜底。
enum JSONValue {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(data: Data) throws {
        self = JSONValue(any: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    init(any: Any) {
        switch any {
        case let dict as [String: Any]:
            self = .object(dict.mapValues(JSONValue.init(any:)))
        case let array as [Any]:
            self = .array(array.map(JSONValue.init(any:)))
        case let string as String:
            self = .string(string)
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            self = .bool(number.boolValue)
        case let number as NSNumber:
            self = .number(number.doubleValue)
        default:
            self = .null
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    subscript(index: Int) -> JSONValue? {
        if case .array(let array) = self, array.indices.contains(index) { return array[index] }
        return nil
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// 数字；字符串形如 "100" 也尝试转换（Kimi / DeepSeek 接口会返回字符串数字）
    var double: Double? {
        switch self {
        case .number(let d): return d
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    var int: Int? { double.map(Int.init) }

    var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// ISO 8601 日期（兼容任意精度小数秒，如 "2026-01-09T15:23:13.716839300Z"）
    var isoDate: Date? {
        guard let s = string else { return nil }
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSX",
            "yyyy-MM-dd'T'HH:mm:ssX",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: s) { return date }
        }
        return nil
    }

    /// Epoch 毫秒时间戳（GLM nextResetTime）
    var epochMsDate: Date? {
        double.map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}
