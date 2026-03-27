import Testing
import Foundation
@testable import DouyinUploader

/// ConfigStore 测试 — 使用临时目录，不影响真实配置文件
@Suite("ConfigStore 持久化测试")
struct ConfigStoreTests {

    // MARK: - 辅助：创建临时目录中的 store

    /// 每个测试方法用不同的临时目录，保证隔离
    private func makeStore() -> (ConfigStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigStoreTests_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("configs.json")
        let store = ConfigStore(fileURL: fileURL)
        return (store, tempDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - 加载空配置

    @Test("文件不存在时 load 返回空数组")
    func loadReturnsEmptyWhenNoFile() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let configs = try store.load()
        #expect(configs.isEmpty)
    }

    // MARK: - 保存和加载往返

    @Test("save 后 load 能还原配置数组")
    func saveAndLoadRoundTrip() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let config1 = FeishuConfig(name: "测试表格1", appToken: "BascABC", tableId: "tbl001")
        let config2 = FeishuConfig(name: "测试表格2", appToken: "BascDEF", tableId: "tbl002")

        try store.save([config1, config2])
        let loaded = try store.load()

        #expect(loaded.count == 2)
        #expect(loaded[0].name == "测试表格1")
        #expect(loaded[0].appToken == "BascABC")
        #expect(loaded[0].tableId == "tbl001")
        #expect(loaded[1].name == "测试表格2")
    }

    // MARK: - 新增

    @Test("add 新增一条配置")
    func addConfig() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let config = FeishuConfig(name: "新配置", appToken: "BascXXX", tableId: "tblXXX")
        try store.add(config)

        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == config.id)
    }

    @Test("add 相同 ID 时幂等，不重复添加")
    func addIdempotent() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let config = FeishuConfig(name: "重复测试", appToken: "BascYYY", tableId: "tblYYY")
        try store.add(config)
        try store.add(config) // 重复添加

        let loaded = try store.load()
        #expect(loaded.count == 1)
    }

    // MARK: - 更新

    @Test("update 能正确修改配置字段")
    func updateConfig() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let config = FeishuConfig(name: "原始名称", appToken: "BascAAA", tableId: "tblAAA")
        try store.add(config)

        // 构造更新版本（不可变模式）
        let updated = FeishuConfig(
            id: config.id,
            name: "修改后名称",
            appToken: "BascAAA",
            tableId: "tblAAA"
        )
        try store.update(updated)

        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "修改后名称")
        #expect(loaded[0].id == config.id) // ID 不变
    }

    @Test("update 不存在的 ID 时抛出 configNotFound 错误")
    func updateNonExistentConfig() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let ghost = FeishuConfig(name: "幽灵配置", appToken: "BascZZZ", tableId: "tblZZZ")

        // 期望抛出 configNotFound 错误
        var caughtError: ConfigStoreError?
        do {
            try store.update(ghost)
        } catch let e as ConfigStoreError {
            caughtError = e
        }

        #expect(caughtError != nil)
        if case .configNotFound(let id) = caughtError {
            #expect(id == ghost.id)
        } else {
            Issue.record("期望 configNotFound，实际收到 \(String(describing: caughtError))")
        }
    }

    // MARK: - 删除

    @Test("delete 能正确移除配置")
    func deleteConfig() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let config1 = FeishuConfig(name: "配置A", appToken: "BascA", tableId: "tblA")
        let config2 = FeishuConfig(name: "配置B", appToken: "BascB", tableId: "tblB")
        try store.add(config1)
        try store.add(config2)

        try store.delete(id: config1.id)

        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == config2.id)
    }

    @Test("delete 不存在的 ID 时不抛出错误（幂等）")
    func deleteNonExistent() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let randomId = UUID()
        // 不应抛出错误
        try store.delete(id: randomId)

        let loaded = try store.load()
        #expect(loaded.isEmpty)
    }

    // MARK: - 目录自动创建

    @Test("配置目录不存在时自动创建")
    func autoCreateDirectory() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoDirTest_\(UUID().uuidString)", isDirectory: true)
        let nestedDir = tempBase.appendingPathComponent("nested/deep", isDirectory: true)
        let fileURL = nestedDir.appendingPathComponent("configs.json")
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let store = ConfigStore(fileURL: fileURL)
        let config = FeishuConfig(name: "目录测试", appToken: "BascD", tableId: "tblD")

        // save 时应自动创建目录
        try store.save([config])

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Codable 字段正确性

    @Test("authType 和 appId 字段正确序列化")
    func authTypeSerializes() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        var config = FeishuConfig(
            name: "自建应用配置",
            appToken: "BascTenant",
            tableId: "tblTenant",
            authType: .tenantApp
        )
        config.appId = "cli_test123"
        config.hasAppSecret = true

        try store.save([config])
        let loaded = try store.load()

        #expect(loaded[0].authType == .tenantApp)
        #expect(loaded[0].appId == "cli_test123")
        #expect(loaded[0].hasAppSecret == true)
    }
}
