import Foundation
import Testing
@testable import DouyinUploader

@Suite("FeishuConfigViewModel 测试")
struct FeishuConfigViewModelTests {

    private func makeTempStore() -> (ConfigStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("config_vm_test_\(UUID().uuidString)")
        let fileURL = dir.appendingPathComponent("configs.json")
        return (ConfigStore(fileURL: fileURL), dir)
    }

    // MARK: - 加载

    @MainActor
    @Test("loadConfigs 加载已保存的配置")
    func loadConfigs() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = FeishuConfig(name: "测试", appToken: "abc", tableId: "tbl1")
        try store.add(config)

        let vm = FeishuConfigViewModel(store: store)
        #expect(vm.configs.count == 1)
        #expect(vm.configs.first?.name == "测试")
    }

    // MARK: - 新增

    @MainActor
    @Test("startAdding 设置表单状态")
    func startAdding() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FeishuConfigViewModel(store: store)
        vm.startAdding()

        #expect(vm.isAdding == true)
        #expect(vm.isEditing == false)
        #expect(vm.formName.isEmpty)
    }

    // MARK: - URL 解析

    @MainActor
    @Test("parseURLIfNeeded 成功解析飞书 URL")
    func parseURL() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FeishuConfigViewModel(store: store)
        vm.formURL = "https://example.feishu.cn/base/VwGhb123?table=tblY456"
        vm.parseURLIfNeeded()

        #expect(vm.urlParsed == true)
        #expect(vm.formAppToken == "VwGhb123")
        #expect(vm.formTableId == "tblY456")
    }

    @MainActor
    @Test("parseURLIfNeeded 无效 URL")
    func parseInvalidURL() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FeishuConfigViewModel(store: store)
        vm.formURL = "https://google.com"
        vm.parseURLIfNeeded()

        #expect(vm.urlParsed == false)
    }

    @MainActor
    @Test("parseURLIfNeeded 空字符串")
    func parseEmptyURL() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FeishuConfigViewModel(store: store)
        vm.formURL = ""
        vm.parseURLIfNeeded()

        #expect(vm.urlParsed == false)
    }

    // MARK: - 取消

    @MainActor
    @Test("cancelEditing 重置状态")
    func cancelEditing() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FeishuConfigViewModel(store: store)
        vm.isEditing = true
        vm.isAdding = true
        vm.formName = "某个配置"
        vm.cancelEditing()

        #expect(vm.isEditing == false)
        #expect(vm.isAdding == false)
        #expect(vm.formName.isEmpty)
    }

    // MARK: - 删除

    @MainActor
    @Test("requestDelete 设置待删除 ID")
    func requestDelete() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = FeishuConfigViewModel(store: store)
        let id = UUID()
        vm.requestDelete(id: id)

        #expect(vm.configToDelete == id)
        #expect(vm.showDeleteConfirm == true)
    }

    @MainActor
    @Test("confirmDelete 删除后列表更新")
    func confirmDelete() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = FeishuConfig(name: "待删除", appToken: "x", tableId: "y")
        try store.add(config)

        let vm = FeishuConfigViewModel(store: store)
        #expect(vm.configs.count == 1)

        vm.requestDelete(id: config.id)
        vm.confirmDelete()

        #expect(vm.configs.isEmpty)
        #expect(vm.showDeleteConfirm == false)
    }

    // MARK: - 编辑

    @MainActor
    @Test("startEditing 填充表单")
    func startEditing() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = FeishuConfig(name: "运营表格", appToken: "tok123", tableId: "tbl456", authType: .pat)
        try store.add(config)

        let vm = FeishuConfigViewModel(store: store)
        vm.startEditing(config: config)

        #expect(vm.isEditing == true)
        #expect(vm.formName == "运营表格")
        #expect(vm.formAppToken == "tok123")
        #expect(vm.formTableId == "tbl456")
        #expect(vm.formAuthType == .pat)
    }
}
