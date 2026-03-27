import XCTest
@testable import DouyinUploader

final class LogStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: LogStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogStoreTests_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = LogStore(logsDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - 辅助方法

    private func makeLog(
        feishuConfigName: String = "测试配置",
        successCount: Int = 2,
        failedCount: Int = 1,
        daysAgo: Int = 0
    ) -> ExecutionLog {
        let startedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        var log = ExecutionLog(
            startedAt: startedAt,
            feishuConfigName: feishuConfigName,
            total: successCount + failedCount
        )
        log.finishedAt = startedAt.addingTimeInterval(60)
        log.successCount = successCount
        log.failedCount = failedCount
        log.addEntry(level: .info, message: "开始执行")
        log.addEntry(level: .success, message: "任务1完成")
        log.addEntry(level: .error, message: "任务2失败")
        return log
    }

    // MARK: - 保存与读取测试

    func testSaveAndLoadAll() throws {
        let log1 = makeLog(feishuConfigName: "配置A")
        let log2 = makeLog(feishuConfigName: "配置B")

        try store.saveLog(log1)
        try store.saveLog(log2)

        let all = store.loadAll()
        XCTAssertEqual(all.count, 2)

        let names = Set(all.map { $0.feishuConfigName })
        XCTAssertTrue(names.contains("配置A"))
        XCTAssertTrue(names.contains("配置B"))
    }

    func testLoadAllReturnsSummaryWithEmptyEntries() throws {
        var log = makeLog()
        log.addEntry(level: .info, message: "详细条目")
        try store.saveLog(log)

        let all = store.loadAll()
        XCTAssertEqual(all.count, 1)
        // 摘要模式下 entries 应为空
        XCTAssertEqual(all.first?.entries.count, 0)
    }

    func testLoadAllReturnsEmptyWhenNoLogs() {
        let all = store.loadAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testLoadLogReturnsFullEntries() throws {
        let log = makeLog()
        try store.saveLog(log)

        let loaded = store.loadLog(id: log.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, log.id)
        XCTAssertFalse(loaded?.entries.isEmpty ?? true)
    }

    func testLoadLogReturnsNilForUnknownId() {
        let result = store.loadLog(id: UUID())
        XCTAssertNil(result)
    }

    // MARK: - 删除测试

    func testDeleteLog() throws {
        let log = makeLog()
        try store.saveLog(log)

        XCTAssertEqual(store.loadAll().count, 1)

        store.deleteLog(id: log.id)
        XCTAssertEqual(store.loadAll().count, 0)
    }

    func testDeleteNonExistentLogDoesNotCrash() {
        // 删除不存在的日志不应崩溃
        store.deleteLog(id: UUID())
    }

    // MARK: - 清理测试

    func testCleanupRemovesOldLogs() throws {
        let oldLog = makeLog(feishuConfigName: "旧日志", daysAgo: 35)
        let newLog = makeLog(feishuConfigName: "新日志", daysAgo: 0)

        try store.saveLog(oldLog)
        try store.saveLog(newLog)

        XCTAssertEqual(store.loadAll().count, 2)

        store.cleanup(retentionDays: 30)

        let remaining = store.loadAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.feishuConfigName, "新日志")
    }

    func testCleanupKeepsLogsWithinRetentionPeriod() throws {
        let log = makeLog(daysAgo: 10)
        try store.saveLog(log)

        store.cleanup(retentionDays: 30)

        XCTAssertEqual(store.loadAll().count, 1)
    }

    // MARK: - 导出测试

    func testExportLogCreatesFile() throws {
        let log = makeLog()
        try store.saveLog(log)

        let fullLog = store.loadLog(id: log.id)!
        let exportURL = try store.exportLog(fullLog)

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

        let content = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(content.contains("测试配置"))
        XCTAssertTrue(content.contains("执行日志导出"))

        // 清理临时文件
        try? FileManager.default.removeItem(at: exportURL)
    }

    func testExportLogContainsDesensitizedContent() throws {
        var log = makeLog()
        log.addEntry(level: .info, message: "cookie=abcdefghij12345; session_id=xyz123456789")
        try store.saveLog(log)

        let fullLog = store.loadLog(id: log.id)!
        let exportURL = try store.exportLog(fullLog)

        let content = try String(contentsOf: exportURL, encoding: .utf8)
        // 敏感值超过8位的部分应被脱敏替换
        XCTAssertFalse(content.contains("abcdefghij12345"))
        XCTAssertFalse(content.contains("xyz123456789"))

        try? FileManager.default.removeItem(at: exportURL)
    }

    // MARK: - 排序测试

    func testLoadAllSortedByDateDescending() throws {
        let older = makeLog(feishuConfigName: "较早", daysAgo: 2)
        let newer = makeLog(feishuConfigName: "较新", daysAgo: 0)

        try store.saveLog(older)
        try store.saveLog(newer)

        let all = store.loadAll()
        XCTAssertEqual(all.first?.feishuConfigName, "较新")
        XCTAssertEqual(all.last?.feishuConfigName, "较早")
    }
}
