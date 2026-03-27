import Foundation

// MARK: - 用户信息模型

/// 抖音用户信息（从创作者中心 API 获取）
struct DouyinUserInfo: Codable, Equatable {
    /// 抖音号（唯一标识）
    let uniqueId: String
    /// 昵称
    let nickname: String
    /// 头像 URL
    let avatarUrl: String?
}

// MARK: - 扫码登录状态

/// 二维码扫码状态
enum QRConnectStatus: Equatable {
    /// 等待用户扫码
    case waiting
    /// 已扫码，等待用户在手机上确认
    case scanned
    /// 用户已确认，携带跳转 URL
    case confirmed(redirectURL: String)
    /// 二维码已过期
    case expired
}

// MARK: - 错误类型

/// 抖音登录相关错误
enum DouyinLoginError: LocalizedError {
    case invalidResponse
    case qrCodeFetchFailed(String)
    case qrCheckFailed(String)
    case loginCompletionFailed(String)
    case userInfoFetchFailed(String)
    case noCookiesReceived
    case cookiesMissingRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器返回了无效的响应格式"
        case .qrCodeFetchFailed(let msg):
            return "获取二维码失败：\(msg)"
        case .qrCheckFailed(let msg):
            return "扫码状态查询失败：\(msg)"
        case .loginCompletionFailed(let msg):
            return "完成登录失败：\(msg)"
        case .userInfoFetchFailed(let msg):
            return "获取用户信息失败：\(msg)"
        case .noCookiesReceived:
            return "登录后未收到任何 Cookie"
        case .cookiesMissingRequired:
            return "Cookie 缺少必要字段，登录可能未完成"
        }
    }
}

// MARK: - 重定向拦截代理

/// URLSession 代理：拦截重定向时的 Set-Cookie，并终止重定向
/// 抖音登录成功后会通过 302 重定向携带 Set-Cookie，需要在重定向前截取
private final class RedirectInterceptor: NSObject, URLSessionTaskDelegate {

    /// 拦截到的响应（包含 Set-Cookie 头）
    private(set) var capturedResponse: HTTPURLResponse?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        // 记录触发重定向的响应（其中含有 Set-Cookie）
        capturedResponse = response
        // 返回 nil 表示拒绝跟随重定向，让请求在此终止
        return nil
    }
}

// MARK: - 抖音登录服务

/// 抖音 SSO 扫码登录服务
/// 使用抖音创作者中心的 SSO 接口完成二维码登录流程
final class DouyinLoginService {

    // MARK: - API 常量

    private enum API {
        /// 获取二维码接口
        static let qrCodeURL = "https://sso.douyin.com/get_qrcode/?service_url=https://creator.douyin.com&aid=2906"
        /// 查询扫码状态接口（需要拼接 token）
        static let qrCheckBase = "https://sso.douyin.com/check_qrconnect/"
        /// 创作者中心用户信息接口
        static let userInfoURL = "https://creator.douyin.com/web/api/media/user/info"
        /// SSO 服务的 aid 参数
        static let aid = "2906"
    }

    // MARK: - 获取二维码

    /// 请求二维码图片 URL 和登录 Token
    /// - Returns: (imageURL: 二维码图片地址, token: 用于轮询的 token)
    /// - Throws: DouyinLoginError
    func getQRCode() async throws -> (imageURL: String, token: String) {
        guard let url = URL(string: API.qrCodeURL) else {
            throw DouyinLoginError.qrCodeFetchFailed("URL 格式错误")
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://creator.douyin.com", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DouyinLoginError.qrCodeFetchFailed("HTTP 状态码异常")
        }

        // 解析响应 JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DouyinLoginError.invalidResponse
        }

        // 兼容两种可能的 key 名称
        let imageURL: String
        if let url = json["qrcode_index_url"] as? String {
            imageURL = url
        } else if let url = json["qr_image_url"] as? String {
            imageURL = url
        } else {
            throw DouyinLoginError.qrCodeFetchFailed("响应中缺少二维码图片 URL")
        }

        guard let token = json["token"] as? String else {
            throw DouyinLoginError.qrCodeFetchFailed("响应中缺少 token")
        }

        return (imageURL: imageURL, token: token)
    }

    // MARK: - 轮询扫码状态

    /// 查询二维码扫码状态
    /// - Parameter token: 从 getQRCode 获取的 token
    /// - Returns: 当前扫码状态
    /// - Throws: DouyinLoginError
    func checkQRConnect(token: String) async throws -> QRConnectStatus {
        var components = URLComponents(string: API.qrCheckBase)
        components?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "aid", value: API.aid)
        ]

        guard let url = components?.url else {
            throw DouyinLoginError.qrCheckFailed("URL 构建失败")
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://creator.douyin.com", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DouyinLoginError.qrCheckFailed("HTTP 状态码异常")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DouyinLoginError.invalidResponse
        }

        // status 字段解析
        // 1: 等待扫码, 2: 已扫码, 3: 确认登录（有 redirect_url）, 4: 过期
        let statusCode = json["status"] as? Int ?? 1

        switch statusCode {
        case 1:
            return .waiting
        case 2:
            return .scanned
        case 3:
            if let redirectURL = json["redirect_url"] as? String {
                return .confirmed(redirectURL: redirectURL)
            } else {
                throw DouyinLoginError.qrCheckFailed("确认登录但缺少 redirect_url")
            }
        case 4:
            return .expired
        default:
            return .waiting
        }
    }

    // MARK: - 完成登录，获取 Cookie

    /// 访问重定向 URL 以获取登录 Cookie
    /// 通过拦截重定向响应的 Set-Cookie 头来获取 Cookie
    /// - Parameter redirectURL: 从 checkQRConnect 获取的 redirectURL
    /// - Returns: 登录成功后的 Cookie 数组
    /// - Throws: DouyinLoginError
    func completeLogin(redirectURL: String) async throws -> [HTTPCookie] {
        guard let url = URL(string: redirectURL) else {
            throw DouyinLoginError.loginCompletionFailed("重定向 URL 格式错误：\(redirectURL)")
        }

        // 使用重定向拦截代理
        let interceptor = RedirectInterceptor()
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpShouldSetCookies = false  // 手动管理 Cookie
        sessionConfig.httpCookieAcceptPolicy = .never

        let session = URLSession(configuration: sessionConfig, delegate: interceptor, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (_, response) = try await session.data(for: request)

        // 收集 Cookie：优先从拦截到的重定向响应中取，其次从最终响应中取
        var allCookies: [HTTPCookie] = []

        // 从拦截的重定向响应中提取 Cookie
        if let capturedResponse = interceptor.capturedResponse,
           let setCookieHeaders = capturedResponse.allHeaderFields as? [String: String] {
            let cookies = HTTPCookie.cookies(
                withResponseHeaderFields: setCookieHeaders,
                for: capturedResponse.url ?? url
            )
            allCookies.append(contentsOf: cookies)
        }

        // 从最终响应中也尝试提取（有时 Cookie 在最终响应中）
        if let httpResponse = response as? HTTPURLResponse,
           let setCookieHeaders = httpResponse.allHeaderFields as? [String: String] {
            let cookies = HTTPCookie.cookies(
                withResponseHeaderFields: setCookieHeaders,
                for: httpResponse.url ?? url
            )
            // 去重（以 name+domain 为键）
            let existingKeys = Set(allCookies.map { "\($0.name)_\($0.domain)" })
            let newCookies = cookies.filter { !existingKeys.contains("\($0.name)_\($0.domain)") }
            allCookies.append(contentsOf: newCookies)
        }

        guard !allCookies.isEmpty else {
            throw DouyinLoginError.noCookiesReceived
        }

        return allCookies
    }

    // MARK: - 获取用户信息

    /// 使用登录 Cookie 请求创作者中心获取用户信息
    /// - Parameter cookies: 登录成功后的 Cookie 数组
    /// - Returns: 用户信息（uniqueId、nickname、avatarUrl）
    /// - Throws: DouyinLoginError
    func fetchUserInfo(cookies: [HTTPCookie]) async throws -> DouyinUserInfo {
        guard let url = URL(string: API.userInfoURL) else {
            throw DouyinLoginError.userInfoFetchFailed("用户信息接口 URL 格式错误")
        }

        // 将 Cookie 拼接为请求头字符串
        let cookieHeader = cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        var request = URLRequest(url: url)
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://creator.douyin.com", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DouyinLoginError.userInfoFetchFailed("HTTP 状态码异常")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DouyinLoginError.invalidResponse
        }

        // 从嵌套结构中提取用户信息
        // 通常结构为 { "data": { "user": { "unique_id": ..., "nickname": ..., "avatar_url": ... } } }
        let userDict: [String: Any]?
        if let data = json["data"] as? [String: Any],
           let user = data["user"] as? [String: Any] {
            userDict = user
        } else if let user = json["user"] as? [String: Any] {
            userDict = user
        } else {
            userDict = json
        }

        guard let userDict = userDict else {
            throw DouyinLoginError.userInfoFetchFailed("响应格式不符合预期")
        }

        // 兼容多种 key 格式
        let uniqueId = userDict["unique_id"] as? String
            ?? userDict["uniqueId"] as? String
            ?? userDict["sec_uid"] as? String
            ?? UUID().uuidString  // 兜底：生成临时 ID

        let nickname = userDict["nickname"] as? String
            ?? userDict["name"] as? String
            ?? "未知用户"

        let avatarUrl = userDict["avatar_url"] as? String
            ?? userDict["avatar_uri"] as? String
            ?? userDict["avatar_thumb"] as? String

        return DouyinUserInfo(
            uniqueId: uniqueId,
            nickname: nickname,
            avatarUrl: avatarUrl
        )
    }

    // MARK: - Cookie 有效性检测

    /// 检测指定账号的 Cookie 是否仍然有效
    /// 通过请求创作者中心用户信息接口来判断
    /// - Parameter uniqueId: 抖音号
    /// - Returns: Cookie 有效返回 true，否则 false
    func validateCookies(uniqueId: String) async -> Bool {
        let cookieManager = DouyinCookieManager()
        guard let cookies = try? cookieManager.loadCookies(uniqueId: uniqueId),
              !cookies.isEmpty else {
            return false
        }

        do {
            let _ = try await fetchUserInfo(cookies: cookies)
            return true
        } catch {
            return false
        }
    }
}
