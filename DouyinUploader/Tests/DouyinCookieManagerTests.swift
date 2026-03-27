import Testing
import Foundation
@testable import DouyinUploader

/// DouyinCookieManager 测试
/// 注意：Keychain 在测试环境中正常可用（macOS 沙箱外）
/// 每个测试使用唯一 uniqueId 确保隔离，测试后清理 Keychain 条目
@Suite("DouyinCookieManager Cookie 管理测试")
struct DouyinCookieManagerTests {

    // MARK: - 辅助

    /// 创建测试用 Cookie 数组
    private func makeCookies(domain: String = ".douyin.com") -> [HTTPCookie] {
        var cookies: [HTTPCookie] = []

        if let c1 = HTTPCookie(properties: [
            .name: "sessionid",
            .value: "test_session_value_abc123",
            .domain: domain,
            .path: "/"
        ]) {
            cookies.append(c1)
        }

        if let c2 = HTTPCookie(properties: [
            .name: "uid_tt",
            .value: "user_tt_id_xyz789",
            .domain: domain,
            .path: "/",
            .secure: "TRUE"
        ]) {
            cookies.append(c2)
        }

        if let c3 = HTTPCookie(properties: [
            .name: "passport_csrf_token",
            .value: "csrf_token_value_def456",
            .domain: domain,
            .path: "/"
        ]) {
            cookies.append(c3)
        }

        return cookies
    }

    /// 生成唯一的测试 uniqueId，避免测试间干扰
    private func makeUniqueId() -> String {
        "test_\(UUID().uuidString.prefix(8).lowercased())"
    }

    /// 清理 Keychain 中的测试条目
    private func cleanup(uniqueId: String) {
        let manager = DouyinCookieManager()
        manager.deleteAll(uniqueId: uniqueId)
    }

    // MARK: - Cookie Key 生成

    @Test("cookieKey 生成格式正确")
    func cookieKeyFormat() {
        let key = DouyinCookieManager.cookieKey(for: "dyfx750s5c44")
        #expect(key == "douyin.cookie.dyfx750s5c44")
    }

    @Test("userInfoKey 生成格式正确")
    func userInfoKeyFormat() {
        let key = DouyinCookieManager.userInfoKey(for: "dyfx750s5c44")
        #expect(key == "douyin.userinfo.dyfx750s5c44")
    }

    // MARK: - Cookie 存储与读取

    @Test("saveCookies 后 loadCookies 能正确还原")
    func saveAndLoadCookiesRoundTrip() throws {
        let uniqueId = makeUniqueId()
        defer { cleanup(uniqueId: uniqueId) }

        let manager = DouyinCookieManager()
        let originalCookies = makeCookies()
        #expect(!originalCookies.isEmpty, "测试 Cookie 不应为空")

        try manager.saveCookies(uniqueId: uniqueId, cookies: originalCookies)
        let loaded = try manager.loadCookies(uniqueId: uniqueId)

        #expect(loaded != nil)
        #expect(loaded!.count == originalCookies.count)
    }

    @Test("Cookie 的 name 和 value 正确保留")
    func cookieNameValuePreserved() throws {
        let uniqueId = makeUniqueId()
        defer { cleanup(uniqueId: uniqueId) }

        let manager = DouyinCookieManager()
        let originalCookies = makeCookies()

        try manager.saveCookies(uniqueId: uniqueId, cookies: originalCookies)
        let loaded = try manager.loadCookies(uniqueId: uniqueId)!

        // 以 name 为键构建字典，便于断言
        let cookieMap = Dictionary(uniqueKeysWithValues: loaded.map { ($0.name, $0.value) })

        #expect(cookieMap["sessionid"] == "test_session_value_abc123")
        #expect(cookieMap["uid_tt"] == "user_tt_id_xyz789")
        #expect(cookieMap["passport_csrf_token"] == "csrf_token_value_def456")
    }

    @Test("Cookie 的 domain 和 path 正确保留")
    func cookieDomainPathPreserved() throws {
        let uniqueId = makeUniqueId()
        defer { cleanup(uniqueId: uniqueId) }

        let manager = DouyinCookieManager()
        let originalCookies = makeCookies(domain: ".creator.douyin.com")

        try manager.saveCookies(uniqueId: uniqueId, cookies: originalCookies)
        let loaded = try manager.loadCookies(uniqueId: uniqueId)!

        for cookie in loaded {
            #expect(cookie.domain == ".creator.douyin.com")
            #expect(cookie.path == "/")
        }
    }

    @Test("不同 uniqueId 的 Cookie 互不干扰")
    func differentUniqueIdsAreIsolated() throws {
        let uniqueId1 = makeUniqueId()
        let uniqueId2 = makeUniqueId()
        defer {
            cleanup(uniqueId: uniqueId1)
            cleanup(uniqueId: uniqueId2)
        }

        let manager = DouyinCookieManager()

        // 为两个账号存储不同的 Cookie
        if let cookie1 = HTTPCookie(properties: [
            .name: "sessionid",
            .value: "session_for_account_1",
            .domain: ".douyin.com",
            .path: "/"
        ]) {
            try manager.saveCookies(uniqueId: uniqueId1, cookies: [cookie1])
        }

        if let cookie2 = HTTPCookie(properties: [
            .name: "sessionid",
            .value: "session_for_account_2",
            .domain: ".douyin.com",
            .path: "/"
        ]) {
            try manager.saveCookies(uniqueId: uniqueId2, cookies: [cookie2])
        }

        let loaded1 = try manager.loadCookies(uniqueId: uniqueId1)!
        let loaded2 = try manager.loadCookies(uniqueId: uniqueId2)!

        #expect(loaded1.first?.value == "session_for_account_1")
        #expect(loaded2.first?.value == "session_for_account_2")
    }

    // MARK: - Cookie 不存在时

    @Test("loadCookies 在未存储时返回 nil")
    func loadCookiesReturnsNilWhenAbsent() throws {
        let uniqueId = makeUniqueId()
        // 不需要 cleanup，因为什么都没存

        let manager = DouyinCookieManager()
        let loaded = try manager.loadCookies(uniqueId: uniqueId)
        #expect(loaded == nil)
    }

    // MARK: - Cookie 删除

    @Test("deleteCookies 后 loadCookies 返回 nil")
    func deleteCookies() throws {
        let uniqueId = makeUniqueId()

        let manager = DouyinCookieManager()
        try manager.saveCookies(uniqueId: uniqueId, cookies: makeCookies())

        // 确认已存储
        let beforeDelete = try manager.loadCookies(uniqueId: uniqueId)
        #expect(beforeDelete != nil)

        // 删除
        try manager.deleteCookies(uniqueId: uniqueId)

        // 确认已清除
        let afterDelete = try manager.loadCookies(uniqueId: uniqueId)
        #expect(afterDelete == nil)
    }

    @Test("deleteCookies 在 Cookie 不存在时不抛出错误")
    func deleteCookiesWhenAbsent() throws {
        let uniqueId = makeUniqueId()
        let manager = DouyinCookieManager()
        // 不应抛出错误
        try manager.deleteCookies(uniqueId: uniqueId)
    }

    // MARK: - 用户信息存储

    @Test("saveUserInfo 后 loadUserInfo 能正确还原")
    func saveAndLoadUserInfo() throws {
        let uniqueId = makeUniqueId()
        defer { cleanup(uniqueId: uniqueId) }

        let manager = DouyinCookieManager()
        let userInfo = DouyinUserInfo(
            uniqueId: uniqueId,
            nickname: "测试用户昵称",
            avatarUrl: "https://example.com/avatar.jpg"
        )

        try manager.saveUserInfo(uniqueId: uniqueId, userInfo: userInfo)
        let loaded = try manager.loadUserInfo(uniqueId: uniqueId)

        #expect(loaded != nil)
        #expect(loaded?.uniqueId == uniqueId)
        #expect(loaded?.nickname == "测试用户昵称")
        #expect(loaded?.avatarUrl == "https://example.com/avatar.jpg")
    }

    @Test("saveUserInfo 支持 nil avatarUrl")
    func saveUserInfoWithNilAvatar() throws {
        let uniqueId = makeUniqueId()
        defer { cleanup(uniqueId: uniqueId) }

        let manager = DouyinCookieManager()
        let userInfo = DouyinUserInfo(uniqueId: uniqueId, nickname: "无头像用户", avatarUrl: nil)

        try manager.saveUserInfo(uniqueId: uniqueId, userInfo: userInfo)
        let loaded = try manager.loadUserInfo(uniqueId: uniqueId)

        #expect(loaded?.avatarUrl == nil)
        #expect(loaded?.nickname == "无头像用户")
    }

    @Test("loadUserInfo 在未存储时返回 nil")
    func loadUserInfoReturnsNilWhenAbsent() throws {
        let uniqueId = makeUniqueId()
        let manager = DouyinCookieManager()
        let loaded = try manager.loadUserInfo(uniqueId: uniqueId)
        #expect(loaded == nil)
    }

    @Test("deleteUserInfo 后 loadUserInfo 返回 nil")
    func deleteUserInfo() throws {
        let uniqueId = makeUniqueId()

        let manager = DouyinCookieManager()
        let userInfo = DouyinUserInfo(uniqueId: uniqueId, nickname: "待删除用户", avatarUrl: nil)
        try manager.saveUserInfo(uniqueId: uniqueId, userInfo: userInfo)

        try manager.deleteUserInfo(uniqueId: uniqueId)

        let loaded = try manager.loadUserInfo(uniqueId: uniqueId)
        #expect(loaded == nil)
    }

    // MARK: - deleteAll 联合删除

    @Test("deleteAll 同时清除 Cookie 和用户信息")
    func deleteAll() throws {
        let uniqueId = makeUniqueId()

        let manager = DouyinCookieManager()
        try manager.saveCookies(uniqueId: uniqueId, cookies: makeCookies())
        let userInfo = DouyinUserInfo(uniqueId: uniqueId, nickname: "待全量删除", avatarUrl: nil)
        try manager.saveUserInfo(uniqueId: uniqueId, userInfo: userInfo)

        manager.deleteAll(uniqueId: uniqueId)

        let cookies = try manager.loadCookies(uniqueId: uniqueId)
        let loadedUserInfo = try manager.loadUserInfo(uniqueId: uniqueId)

        #expect(cookies == nil)
        #expect(loadedUserInfo == nil)
    }

    @Test("deleteAll 在数据不存在时不崩溃")
    func deleteAllWhenAbsent() {
        let uniqueId = makeUniqueId()
        let manager = DouyinCookieManager()
        // 不应抛出异常
        manager.deleteAll(uniqueId: uniqueId)
    }

    // MARK: - 更新 Cookie

    @Test("重复 saveCookies 会覆盖旧值")
    func saveCookiesOverwritesOldValue() throws {
        let uniqueId = makeUniqueId()
        defer { cleanup(uniqueId: uniqueId) }

        let manager = DouyinCookieManager()

        // 第一次存储
        if let cookie = HTTPCookie(properties: [
            .name: "sessionid",
            .value: "old_session",
            .domain: ".douyin.com",
            .path: "/"
        ]) {
            try manager.saveCookies(uniqueId: uniqueId, cookies: [cookie])
        }

        // 第二次存储（覆盖）
        if let cookie = HTTPCookie(properties: [
            .name: "sessionid",
            .value: "new_session",
            .domain: ".douyin.com",
            .path: "/"
        ]) {
            try manager.saveCookies(uniqueId: uniqueId, cookies: [cookie])
        }

        let loaded = try manager.loadCookies(uniqueId: uniqueId)!
        #expect(loaded.first?.value == "new_session")
    }
}
