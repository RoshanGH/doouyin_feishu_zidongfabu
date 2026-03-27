import Testing
import Foundation
@testable import DouyinUploader

/// AccountStore 持久化测试
/// 使用临时目录隔离，不影响真实数据文件
@Suite("AccountStore 持久化测试")
struct AccountStoreTests {

    // MARK: - 辅助

    /// 在临时目录中创建 AccountStore，每个测试独立
    private func makeStore() -> (AccountStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountStoreTests_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("accounts.json")
        let store = AccountStore(fileURL: fileURL)
        return (store, tempDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// 创建测试账号
    private func makeAccount(
        uniqueId: String = "test_user_\(UUID().uuidString.prefix(6))",
        nickname: String = "测试昵称",
        avatarUrl: String? = nil,
        isValid: Bool = true
    ) -> DouyinAccount {
        DouyinAccount(
            uniqueId: uniqueId,
            nickname: nickname,
            avatarUrl: avatarUrl,
            loginTime: Date(),
            isValid: isValid
        )
    }

    // MARK: - 加载空数据

    @Test("文件不存在时 loadAll 返回空数组")
    func loadAllReturnsEmptyWhenNoFile() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let accounts = try store.loadAll()
        #expect(accounts.isEmpty)
    }

    // MARK: - 保存和加载往返

    @Test("save 后 loadAll 能还原账号数组")
    func saveAndLoadAllRoundTrip() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let account1 = makeAccount(uniqueId: "user001", nickname: "用户一")
        let account2 = makeAccount(uniqueId: "user002", nickname: "用户二")

        try store.save([account1, account2])
        let loaded = try store.loadAll()

        #expect(loaded.count == 2)
        #expect(loaded[0].uniqueId == "user001")
        #expect(loaded[0].nickname == "用户一")
        #expect(loaded[1].uniqueId == "user002")
        #expect(loaded[1].nickname == "用户二")
    }

    @Test("账号的所有字段都能正确序列化和反序列化")
    func allFieldsSerializeCorrectly() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let loginTime = Date(timeIntervalSince1970: 1_700_000_000)  // 固定时间，避免精度问题
        let account = DouyinAccount(
            uniqueId: "dyfx750s5c44",
            nickname: "测试昵称",
            avatarUrl: "https://example.com/avatar.jpg",
            loginTime: loginTime,
            isValid: true
        )

        try store.save([account])
        let loaded = try store.loadAll()

        #expect(loaded.count == 1)
        let a = loaded[0]
        #expect(a.uniqueId == "dyfx750s5c44")
        #expect(a.nickname == "测试昵称")
        #expect(a.avatarUrl == "https://example.com/avatar.jpg")
        #expect(a.isValid == true)
        // 日期比较允许 1 秒误差（ISO8601 精度）
        #expect(abs(a.loginTime.timeIntervalSince(loginTime)) < 1.0)
    }

    @Test("isValid = false 的账号正确保存")
    func invalidAccountSerializes() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let account = makeAccount(uniqueId: "expired_user", isValid: false)
        try store.save([account])
        let loaded = try store.loadAll()

        #expect(loaded[0].isValid == false)
    }

    @Test("avatarUrl 为 nil 时正确序列化")
    func nullAvatarUrlSerializes() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let account = makeAccount(uniqueId: "no_avatar_user", avatarUrl: nil)
        try store.save([account])
        let loaded = try store.loadAll()

        #expect(loaded[0].avatarUrl == nil)
    }

    // MARK: - add 新增

    @Test("add 新增一条账号记录")
    func addAccount() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let account = makeAccount(uniqueId: "new_user")
        try store.add(account)

        let loaded = try store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == account.id)
        #expect(loaded[0].uniqueId == "new_user")
    }

    @Test("add 相同 uniqueId 时覆盖旧记录（幂等更新）")
    func addWithSameUniqueIdUpdates() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let account1 = makeAccount(uniqueId: "shared_user", nickname: "旧昵称")
        try store.add(account1)

        // 相同 uniqueId，但昵称不同
        let account2 = DouyinAccount(
            id: UUID(),  // 不同 UUID
            uniqueId: "shared_user",
            nickname: "新昵称",
            loginTime: Date(),
            isValid: true
        )
        try store.add(account2)

        let loaded = try store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].nickname == "新昵称")
    }

    @Test("add 多个不同账号后 loadAll 返回全部")
    func addMultipleAccounts() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let accounts = (1...5).map { i in
            makeAccount(uniqueId: "user_\(i)", nickname: "用户\(i)")
        }

        for account in accounts {
            try store.add(account)
        }

        let loaded = try store.loadAll()
        #expect(loaded.count == 5)
    }

    // MARK: - update 更新

    @Test("update 能正确修改账号字段")
    func updateAccount() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let account = makeAccount(uniqueId: "update_test", nickname: "原始昵称", isValid: true)
        try store.add(account)

        // 构造更新版本（不可变模式）
        let updated = DouyinAccount(
            id: account.id,
            uniqueId: account.uniqueId,
            nickname: "新昵称",
            avatarUrl: "https://example.com/new_avatar.jpg",
            loginTime: account.loginTime,
            isValid: false
        )
        try store.update(updated)

        let loaded = try store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].nickname == "新昵称")
        #expect(loaded[0].avatarUrl == "https://example.com/new_avatar.jpg")
        #expect(loaded[0].isValid == false)
        #expect(loaded[0].id == account.id)  // ID 不变
    }

    @Test("update 不存在的 ID 时抛出 accountNotFound 错误")
    func updateNonExistentAccount() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let ghost = makeAccount(uniqueId: "ghost_user")

        var caughtError: AccountStoreError?
        do {
            try store.update(ghost)
        } catch let e as AccountStoreError {
            caughtError = e
        }

        #expect(caughtError != nil)
        if case .accountNotFound(let id) = caughtError {
            #expect(id == ghost.id)
        } else {
            Issue.record("期望 accountNotFound，实际收到 \(String(describing: caughtError))")
        }
    }

    @Test("update 只修改目标账号，其他账号不受影响")
    func updateDoesNotAffectOtherAccounts() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let account1 = makeAccount(uniqueId: "user_a", nickname: "用户A")
        let account2 = makeAccount(uniqueId: "user_b", nickname: "用户B")
        try store.add(account1)
        try store.add(account2)

        let updatedAccount1 = DouyinAccount(
            id: account1.id,
            uniqueId: account1.uniqueId,
            nickname: "用户A已更新",
            loginTime: account1.loginTime,
            isValid: account1.isValid
        )
        try store.update(updatedAccount1)

        let loaded = try store.loadAll()
        let loadedAccount2 = loaded.first(where: { $0.id == account2.id })
        #expect(loadedAccount2?.nickname == "用户B")
    }

    // MARK: - delete 删除

    @Test("delete 能正确移除账号")
    func deleteAccount() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let account1 = makeAccount(uniqueId: "user_to_keep", nickname: "保留用户")
        let account2 = makeAccount(uniqueId: "user_to_delete", nickname: "删除用户")
        try store.add(account1)
        try store.add(account2)

        try store.delete(id: account2.id)

        let loaded = try store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == account1.id)
    }

    @Test("delete 不存在的 ID 时不抛出错误（幂等）")
    func deleteNonExistentAccount() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let randomId = UUID()
        // 不应抛出错误
        try store.delete(id: randomId)

        let loaded = try store.loadAll()
        #expect(loaded.isEmpty)
    }

    @Test("删除后列表中不再包含该账号")
    func deletedAccountNotInList() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let account = makeAccount(uniqueId: "delete_me")
        try store.add(account)
        try store.delete(id: account.id)

        let loaded = try store.loadAll()
        #expect(!loaded.contains(where: { $0.id == account.id }))
    }

    // MARK: - 目录自动创建

    @Test("配置目录不存在时 save 自动创建目录")
    func autoCreateDirectory() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountAutoDir_\(UUID().uuidString)", isDirectory: true)
        let nestedDir = tempBase.appendingPathComponent("nested/accounts", isDirectory: true)
        let fileURL = nestedDir.appendingPathComponent("accounts.json")
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let store = AccountStore(fileURL: fileURL)
        let account = makeAccount(uniqueId: "dir_test_user")

        // save 时应自动创建深层目录
        try store.save([account])

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - 错误描述

    @Test("AccountStoreError 提供有效的错误描述")
    func errorDescriptions() {
        let testId = UUID()

        let errors: [AccountStoreError] = [
            .accountNotFound(testId)
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!(error.errorDescription?.isEmpty ?? true))
        }

        // 验证 accountNotFound 包含 ID 信息
        if case .accountNotFound = errors[0] {
            #expect(errors[0].errorDescription?.contains(testId.uuidString) == true)
        }
    }

    // MARK: - 多次 save 覆盖

    @Test("多次 save 会全量覆盖，不叠加")
    func saveOverwritesPreviousData() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let first = makeAccount(uniqueId: "first_batch")
        try store.save([first])

        let second = makeAccount(uniqueId: "second_batch")
        try store.save([second])

        let loaded = try store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].uniqueId == "second_batch")
    }

    // MARK: - 保存空数组

    @Test("save 空数组后 loadAll 返回空数组")
    func saveEmptyArray() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let account = makeAccount(uniqueId: "temp_user")
        try store.save([account])

        // 覆盖为空
        try store.save([])

        let loaded = try store.loadAll()
        #expect(loaded.isEmpty)
    }
}
