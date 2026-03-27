import Foundation

/// 抖音 Cookie 管理器
/// Cookie 序列化为 JSON 存入 Keychain，key 格式: "douyin.cookie.{uniqueId}"
/// 用户信息同样存入 Keychain，key 格式: "douyin.userinfo.{uniqueId}"
final class DouyinCookieManager {

    // MARK: - Keychain Key 生成

    /// Cookie 存储的 Keychain key
    static func cookieKey(for uniqueId: String) -> String {
        "douyin.cookie.\(uniqueId)"
    }

    /// 用户信息存储的 Keychain key
    static func userInfoKey(for uniqueId: String) -> String {
        "douyin.userinfo.\(uniqueId)"
    }

    // MARK: - Cookie 的可编码中间结构

    /// HTTPCookie 不直接实现 Codable，需要先转换为字典再序列化
    private struct CookieDTO: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let isSecure: Bool
        let isHTTPOnly: Bool
        let expiresDate: Date?

        /// 从 HTTPCookie 创建 DTO
        init(cookie: HTTPCookie) {
            self.name = cookie.name
            self.value = cookie.value
            self.domain = cookie.domain
            self.path = cookie.path
            self.isSecure = cookie.isSecure
            self.isHTTPOnly = cookie.isHTTPOnly
            self.expiresDate = cookie.expiresDate
        }

        /// 还原为 HTTPCookie（部分属性 HTTPCookie 不支持，尽量还原）
        func toHTTPCookie() -> HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path
            ]
            if let expires = expiresDate {
                properties[.expires] = expires
            }
            if isSecure {
                properties[.secure] = "TRUE"
            }
            return HTTPCookie(properties: properties)
        }
    }

    // MARK: - 存储

    /// 将 Cookie 数组序列化为 JSON 后存入 Keychain
    /// - Parameters:
    ///   - uniqueId: 抖音号，用于生成 Keychain key
    ///   - cookies: 要保存的 Cookie 列表
    /// - Throws: KeychainError 或 JSON 编码错误
    func saveCookies(uniqueId: String, cookies: [HTTPCookie]) throws {
        let dtos = cookies.map { CookieDTO(cookie: $0) }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(dtos)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }

        try KeychainService.save(key: DouyinCookieManager.cookieKey(for: uniqueId), value: jsonString)
    }

    /// 从 Keychain 读取并反序列化 Cookie 数组
    /// - Parameter uniqueId: 抖音号
    /// - Returns: Cookie 数组，不存在时返回 nil
    /// - Throws: KeychainError 或 JSON 解码错误
    func loadCookies(uniqueId: String) throws -> [HTTPCookie]? {
        guard let jsonString = try KeychainService.loadString(
            key: DouyinCookieManager.cookieKey(for: uniqueId)
        ) else {
            return nil
        }

        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dtos = try decoder.decode([CookieDTO].self, from: data)
        // 过滤掉还原失败的 Cookie
        return dtos.compactMap { $0.toHTTPCookie() }
    }

    /// 从 Keychain 删除指定账号的 Cookie
    /// - Parameter uniqueId: 抖音号
    /// - Throws: KeychainError（找不到时静默忽略）
    func deleteCookies(uniqueId: String) throws {
        try KeychainService.delete(key: DouyinCookieManager.cookieKey(for: uniqueId))
    }

    // MARK: - 用户信息存储

    /// 将用户信息序列化为 JSON 后存入 Keychain
    /// - Parameters:
    ///   - uniqueId: 抖音号
    ///   - userInfo: 用户信息对象
    /// - Throws: KeychainError 或 JSON 编码错误
    func saveUserInfo(uniqueId: String, userInfo: DouyinUserInfo) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(userInfo)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try KeychainService.save(key: DouyinCookieManager.userInfoKey(for: uniqueId), value: jsonString)
    }

    /// 从 Keychain 读取用户信息
    /// - Parameter uniqueId: 抖音号
    /// - Returns: 用户信息，不存在时返回 nil
    /// - Throws: KeychainError 或 JSON 解码错误
    func loadUserInfo(uniqueId: String) throws -> DouyinUserInfo? {
        guard let jsonString = try KeychainService.loadString(
            key: DouyinCookieManager.userInfoKey(for: uniqueId)
        ) else {
            return nil
        }

        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try decoder.decode(DouyinUserInfo.self, from: data)
    }

    /// 从 Keychain 删除指定账号的用户信息
    /// - Parameter uniqueId: 抖音号
    /// - Throws: KeychainError（找不到时静默忽略）
    func deleteUserInfo(uniqueId: String) throws {
        try KeychainService.delete(key: DouyinCookieManager.userInfoKey(for: uniqueId))
    }

    // MARK: - 联合删除

    /// 同时删除指定账号的 Cookie 和用户信息
    /// - Parameter uniqueId: 抖音号
    func deleteAll(uniqueId: String) {
        try? deleteCookies(uniqueId: uniqueId)
        try? deleteUserInfo(uniqueId: uniqueId)
    }
}
