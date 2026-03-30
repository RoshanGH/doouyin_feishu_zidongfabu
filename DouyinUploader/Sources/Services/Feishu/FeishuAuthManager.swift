import Foundation

// MARK: - URLSession 协议（便于测试时注入 mock）

/// URLSession 可测试协议，URLSession 默认实现此协议
protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - 飞书认证错误

/// 飞书认证相关错误
enum FeishuAuthError: LocalizedError {
    case missingCredentials(String)
    case networkError(Error)
    case invalidResponse(String)
    case tokenRequestFailed(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let detail):
            return "凭证缺失：\(detail)"
        case .networkError(let error):
            return "网络请求失败：\(error.localizedDescription)"
        case .invalidResponse(let detail):
            return "响应格式异常：\(detail)"
        case .tokenRequestFailed(let code, let message):
            return "获取 Token 失败（\(code)）：\(message)"
        }
    }
}

// MARK: - token 缓存结构

private struct TokenCache {
    let token: String
    let expiresAt: Date

    /// 是否需要刷新（过期前 5 分钟认为需要刷新）
    var needsRefresh: Bool {
        Date().addingTimeInterval(5 * 60) >= expiresAt
    }
}

// MARK: - 飞书 API Token 管理器

/// 飞书 API Token 管理器（actor 保证并发安全）
/// 支持两种认证方式：
/// 1. PAT（个人访问令牌）：直接用作 Bearer Token
/// 2. 自建应用：用 App ID + Secret → POST /auth/v3/tenant_access_token/internal
///    获取 tenant_access_token，并在过期前5分钟自动刷新
actor FeishuAuthManager {

    // MARK: - 属性

    private let config: FeishuConfig
    private let baseURL: String
    private let session: URLSessionProtocol

    /// tenant_access_token 缓存（仅自建应用使用）
    /// actor 本身保证访问安全，无需额外加锁
    private var tokenCache: TokenCache?

    // MARK: - 初始化

    /// - Parameters:
    ///   - config: 飞书配置
    ///   - baseURL: API 基础 URL
    ///   - session: URLSession 实例（测试时可注入 mock）
    init(
        config: FeishuConfig,
        baseURL: String = "https://open.feishu.cn/open-apis",
        session: URLSessionProtocol = URLSession.shared
    ) {
        self.config = config
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - 公共接口

    /// 获取当前有效 Token
    /// - PAT 认证：直接从 Keychain 读取 PAT
    /// - 自建应用认证：返回有效的 tenant_access_token（必要时自动刷新）
    /// - Returns: Bearer Token 字符串
    /// - Throws: FeishuAuthError
    func getToken() async throws -> String {
        switch config.authType {
        case .pat:
            return try loadPAT()
        case .tenantApp:
            return try await getTenantAccessToken()
        }
    }

    /// 手动清除 token 缓存（测试或登出时使用）
    func clearCache() {
        tokenCache = nil
    }

    // MARK: - PAT 认证

    private func loadPAT() throws -> String {
        let key = KeychainService.patKey(for: config.id)
        guard let pat = try KeychainService.loadString(key: key), !pat.isEmpty else {
            throw FeishuAuthError.missingCredentials("PAT 未配置，请在飞书配置页面填写个人访问令牌")
        }
        return pat
    }

    // MARK: - 自建应用认证

    /// 获取 tenant_access_token，命中缓存则直接返回，否则请求新 token
    private func getTenantAccessToken() async throws -> String {
        // actor 保证互斥访问，直接检查缓存
        if let cache = tokenCache, !cache.needsRefresh {
            return cache.token
        }

        // 缓存不存在或即将过期，重新请求
        return try await requestTenantAccessToken()
    }

    /// 向飞书 API 请求新的 tenant_access_token
    private func requestTenantAccessToken() async throws -> String {
        // 读取 App ID 和 App Secret
        guard let appId = config.appId, !appId.isEmpty else {
            throw FeishuAuthError.missingCredentials("App ID 未配置")
        }
        let secretKey = KeychainService.appSecretKey(for: config.id)
        guard let appSecret = try KeychainService.loadString(key: secretKey), !appSecret.isEmpty else {
            throw FeishuAuthError.missingCredentials("App Secret 未配置，请在飞书配置页面填写")
        }

        // 构造 POST 请求
        let urlString = "\(baseURL)/auth/v3/tenant_access_token/internal"
        guard let url = URL(string: urlString) else {
            throw FeishuAuthError.invalidResponse("无效的 API URL: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "app_id": appId,
            "app_secret": appSecret
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 发送请求
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeishuAuthError.networkError(error)
        }

        // 检查 HTTP 状态码
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw FeishuAuthError.invalidResponse("HTTP \(httpResponse.statusCode)")
        }

        // 解析响应
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FeishuAuthError.invalidResponse("无法解析 JSON 响应")
        }

        let code = json["code"] as? Int ?? -1
        guard code == 0 else {
            let message = json["msg"] as? String ?? "未知错误"
            throw FeishuAuthError.tokenRequestFailed(code: code, message: message)
        }

        guard let token = json["tenant_access_token"] as? String, !token.isEmpty else {
            throw FeishuAuthError.invalidResponse("响应中缺少 tenant_access_token 字段")
        }

        // 获取过期时间（飞书返回秒数，通常为 7200 秒）
        let expireSeconds = json["expire"] as? Int ?? 7200
        let expiresAt = Date().addingTimeInterval(TimeInterval(expireSeconds))

        // 更新缓存（actor 上下文，无需加锁）
        tokenCache = TokenCache(token: token, expiresAt: expiresAt)

        return token
    }
}
