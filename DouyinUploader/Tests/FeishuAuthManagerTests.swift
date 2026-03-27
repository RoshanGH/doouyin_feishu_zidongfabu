import Testing
import Foundation
@testable import DouyinUploader

/// FeishuAuthManager token 缓存逻辑测试
/// 使用 mock URLSession 避免真实网络请求
@Suite("FeishuAuthManager 测试")
struct FeishuAuthManagerTests {

    // MARK: - 辅助：构建测试用 FeishuConfig

    private func makePATConfig() -> FeishuConfig {
        FeishuConfig(
            name: "PAT测试",
            appToken: "BascTest",
            tableId: "tblTest",
            authType: .pat
        )
    }

    private func makeTenantAppConfig(appId: String = "cli_test") -> FeishuConfig {
        var config = FeishuConfig(
            name: "自建应用测试",
            appToken: "BascTest",
            tableId: "tblTest",
            authType: .tenantApp
        )
        config.appId = appId
        return config
    }

    // MARK: - PAT 认证测试

    @Test("PAT 已配置时 getToken 返回 PAT 值")
    func patGetTokenSuccess() async throws {
        let config = makePATConfig()
        let patValue = "pat-testvalue-\(UUID().uuidString)"
        defer { try? KeychainService.delete(key: KeychainService.patKey(for: config.id)) }

        try KeychainService.save(key: KeychainService.patKey(for: config.id), value: patValue)

        let manager = FeishuAuthManager(config: config)
        let token = try await manager.getToken()

        #expect(token == patValue)
    }

    @Test("PAT 未配置时 getToken 抛出 missingCredentials 错误")
    func patMissingThrowsError() async throws {
        let config = makePATConfig()
        // 确保 Keychain 中没有 PAT
        try? KeychainService.delete(key: KeychainService.patKey(for: config.id))

        let manager = FeishuAuthManager(config: config)

        var caughtError: FeishuAuthError?
        do {
            _ = try await manager.getToken()
        } catch let e as FeishuAuthError {
            caughtError = e
        }

        #expect(caughtError != nil)
        if case .missingCredentials = caughtError {
            // 正确：符合预期
        } else {
            Issue.record("期望 missingCredentials，实际收到 \(String(describing: caughtError))")
        }
    }

    // MARK: - 自建应用认证 - 凭证缺失测试

    @Test("自建应用 App ID 为空时抛出 missingCredentials")
    func tenantAppMissingAppIdThrows() async throws {
        var config = makeTenantAppConfig()
        config.appId = nil  // 清空 App ID
        // 确保没有残留 Secret
        try? KeychainService.delete(key: KeychainService.appSecretKey(for: config.id))

        let manager = FeishuAuthManager(config: config)

        var caughtError: FeishuAuthError?
        do {
            _ = try await manager.getToken()
        } catch let e as FeishuAuthError {
            caughtError = e
        }

        #expect(caughtError != nil)
        if case .missingCredentials = caughtError {
            // 正确
        } else {
            Issue.record("期望 missingCredentials，实际收到 \(String(describing: caughtError))")
        }
    }

    @Test("自建应用 App Secret 未配置时抛出 missingCredentials")
    func tenantAppMissingSecretThrows() async throws {
        let config = makeTenantAppConfig(appId: "cli_valid")
        // 确保 Keychain 中没有 Secret
        try? KeychainService.delete(key: KeychainService.appSecretKey(for: config.id))

        let manager = FeishuAuthManager(config: config)

        var caughtError: FeishuAuthError?
        do {
            _ = try await manager.getToken()
        } catch let e as FeishuAuthError {
            caughtError = e
        }

        #expect(caughtError != nil)
        if case .missingCredentials = caughtError {
            // 正确
        } else {
            Issue.record("期望 missingCredentials，实际收到 \(String(describing: caughtError))")
        }
    }

    // MARK: - 缓存逻辑测试（通过 Mock HTTP Server）

    @Test("自建应用认证：API 返回错误 code 时抛出 tokenRequestFailed")
    func tenantTokenRequestFailedError() async throws {
        let config = makeTenantAppConfig(appId: "cli_bad")
        let secretKey = KeychainService.appSecretKey(for: config.id)
        defer { try? KeychainService.delete(key: secretKey) }
        try KeychainService.save(key: secretKey, value: "bad_secret")

        // 构建返回错误 code 的 mock session
        let mockSession = MockURLSession(response: """
            {"code": 10003, "msg": "app not exist"}
            """)

        let manager = FeishuAuthManager(config: config, baseURL: "https://mock.test", session: mockSession)

        var caughtError: FeishuAuthError?
        do {
            _ = try await manager.getToken()
        } catch let e as FeishuAuthError {
            caughtError = e
        }

        #expect(caughtError != nil)
        if case .tokenRequestFailed(let code, _) = caughtError {
            #expect(code == 10003)
        } else {
            Issue.record("期望 tokenRequestFailed，实际收到 \(String(describing: caughtError))")
        }
    }

    @Test("自建应用认证：成功响应后 token 被缓存，第二次调用不再发网络请求")
    func tokenIsCachedAfterSuccess() async throws {
        let config = makeTenantAppConfig(appId: "cli_cache")
        let secretKey = KeychainService.appSecretKey(for: config.id)
        defer { try? KeychainService.delete(key: secretKey) }
        try KeychainService.save(key: secretKey, value: "valid_secret")

        let expectedToken = "t-cachetest-\(UUID().uuidString)"
        let mockSession = MockURLSession(response: """
            {"code": 0, "tenant_access_token": "\(expectedToken)", "expire": 7200}
            """)

        let manager = FeishuAuthManager(config: config, baseURL: "https://mock.test", session: mockSession)

        // 第一次调用
        let token1 = try await manager.getToken()
        // 第二次调用（应命中缓存，requestCount 不增加）
        let token2 = try await manager.getToken()

        #expect(token1 == expectedToken)
        #expect(token2 == expectedToken)
        // 只发了一次网络请求
        #expect(mockSession.requestCount == 1)
    }

    @Test("clearCache 后再次调用 getToken 会重新请求网络")
    func clearCacheForcesRefresh() async throws {
        let config = makeTenantAppConfig(appId: "cli_clear")
        let secretKey = KeychainService.appSecretKey(for: config.id)
        defer { try? KeychainService.delete(key: secretKey) }
        try KeychainService.save(key: secretKey, value: "valid_secret")

        let mockSession = MockURLSession(response: """
            {"code": 0, "tenant_access_token": "t-fresh-token", "expire": 7200}
            """)

        let manager = FeishuAuthManager(config: config, baseURL: "https://mock.test", session: mockSession)

        _ = try await manager.getToken()
        #expect(mockSession.requestCount == 1)

        // 清除缓存后再次调用
        await manager.clearCache()
        _ = try await manager.getToken()
        #expect(mockSession.requestCount == 2)
    }
}

// MARK: - Mock URLSession

/// 用于测试的 mock URLSession，固定返回指定的 JSON 字符串
final class MockURLSession: URLSessionProtocol {
    let responseBody: String
    private(set) var requestCount: Int = 0

    init(response: String) {
        self.responseBody = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        let data = responseBody.data(using: .utf8) ?? Data()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://mock.test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
