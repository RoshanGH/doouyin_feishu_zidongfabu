import Foundation
import Testing
@testable import DouyinUploader

@Suite("HistoryViewModel 测试")
struct HistoryViewModelTests {

    private func makeTempLogStore() -> (LogStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("history_vm_test_\(UUID().uuidString)")
        return (LogStore(logsDirectory: dir), dir)
    }

    @MainActor
    @Test("loadHistory 加载日志列表")
    func loadHistory() throws {
        let (store, dir) = makeTempLogStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var log1 = ExecutionLog(feishuConfigName: "表格A", total: 5)
        log1.successCount = 3
        log1.failedCount = 2
        log1.finishedAt = Date()
        try store.saveLog(log1)

        var log2 = ExecutionLog(feishuConfigName: "表格B", total: 3)
        log2.successCount = 3
        log2.finishedAt = Date()
        try store.saveLog(log2)

        let vm = HistoryViewModel(logStore: store)
        vm.loadHistory()

        #expect(vm.historyList.count == 2)
    }

    @MainActor
    @Test("selectLog 选中后 selectedLog 不为 nil")
    func selectLog() throws {
        let (store, dir) = makeTempLogStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var log = ExecutionLog(feishuConfigName: "选中测试", total: 1)
        log.addEntry(level: .info, message: "测试日志")
        log.finishedAt = Date()
        try store.saveLog(log)

        let vm = HistoryViewModel(logStore: store)
        vm.loadHistory()
        vm.selectLog(id: log.id)

        #expect(vm.selectedLog != nil)
        #expect(vm.selectedLog?.feishuConfigName == "选中测试")
    }

    @MainActor
    @Test("clearSelection 清除选中")
    func clearSelection() throws {
        let (store, dir) = makeTempLogStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var log = ExecutionLog(feishuConfigName: "清除测试", total: 1)
        log.finishedAt = Date()
        try store.saveLog(log)

        let vm = HistoryViewModel(logStore: store)
        vm.loadHistory()
        vm.selectLog(id: log.id)
        #expect(vm.selectedLog != nil)

        vm.clearSelection()
        #expect(vm.selectedLog == nil)
    }

    @MainActor
    @Test("deleteLog 删除后列表更新")
    func deleteLog() throws {
        let (store, dir) = makeTempLogStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var log = ExecutionLog(feishuConfigName: "删除测试", total: 1)
        log.finishedAt = Date()
        try store.saveLog(log)

        let vm = HistoryViewModel(logStore: store)
        vm.loadHistory()
        #expect(vm.historyList.count == 1)

        vm.deleteLog(id: log.id)
        #expect(vm.historyList.isEmpty)
    }

    @MainActor
    @Test("deleteLog 同时清除 selectedLog")
    func deleteSelectedLog() throws {
        let (store, dir) = makeTempLogStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var log = ExecutionLog(feishuConfigName: "删选中", total: 1)
        log.finishedAt = Date()
        try store.saveLog(log)

        let vm = HistoryViewModel(logStore: store)
        vm.loadHistory()
        vm.selectLog(id: log.id)
        vm.deleteLog(id: log.id)

        #expect(vm.selectedLog == nil)
        #expect(vm.historyList.isEmpty)
    }

    // MARK: - 导出测试

    @MainActor
    @Test("exportLog 成功设置 exportURL")
    func exportLogSuccess() throws {
        let (store, dir) = makeTempLogStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var log = ExecutionLog(feishuConfigName: "导出测试", total: 2)
        log.addEntry(level: .info, message: "测试条目")
        log.successCount = 2
        log.finishedAt = Date()
        try store.saveLog(log)

        let vm = HistoryViewModel(logStore: store)
        vm.loadHistory()
        vm.exportLog(id: log.id)

        #expect(vm.exportURL != nil)
        #expect(vm.errorMessage == nil)

        // 清理导出的临时文件
        if let url = vm.exportURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @MainActor
    @Test("exportLog 找不到日志时设置 errorMessage")
    func exportLogNotFound() {
        let (store, dir) = makeTempLogStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = HistoryViewModel(logStore: store)
        vm.exportLog(id: UUID())

        #expect(vm.errorMessage == "找不到要导出的日志")
        #expect(vm.exportURL == nil)
    }

    // MARK: - selectLog 边界情况

    @MainActor
    @Test("selectLog 找不到完整日志时回退到摘要")
    func selectLogFallbackToSummary() throws {
        let (store, dir) = makeTempLogStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var log = ExecutionLog(feishuConfigName: "回退测试", total: 1)
        log.finishedAt = Date()
        try store.saveLog(log)

        let vm = HistoryViewModel(logStore: store)
        vm.loadHistory()

        // 删除文件但不更新列表，模拟文件丢失但列表仍有记录
        store.deleteLog(id: log.id)

        vm.selectLog(id: log.id)
        #expect(vm.selectedLog != nil)
        #expect(vm.selectedLog?.feishuConfigName == "回退测试")
    }
}
