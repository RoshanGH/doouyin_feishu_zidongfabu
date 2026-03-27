import Foundation
import Testing
@testable import DouyinUploader

@Suite("ExecutionLog 测试")
struct ExecutionLogTests {

    @Test("初始化默认值")
    func defaultInit() {
        let log = ExecutionLog(feishuConfigName: "运营表格", total: 12)
        #expect(log.feishuConfigName == "运营表格")
        #expect(log.total == 12)
        #expect(log.successCount == 0)
        #expect(log.failedCount == 0)
        #expect(log.entries.isEmpty)
        #expect(log.finishedAt == nil)
    }

    @Test("addEntry 增加日志条目")
    func addEntry() {
        var log = ExecutionLog(feishuConfigName: "测试", total: 5)
        log.addEntry(level: .info, message: "开始执行")
        log.addEntry(level: .success, message: "任务1成功", taskIndex: 1, taskType: "video", account: "dy123")

        #expect(log.entries.count == 2)
        #expect(log.entries[0].level == .info)
        #expect(log.entries[1].taskIndex == 1)
        #expect(log.entries[1].taskType == "video")
        #expect(log.entries[1].account == "dy123")
    }

    @Test("durationSeconds 计算正确")
    func durationSeconds() {
        var log = ExecutionLog(
            startedAt: Date(timeIntervalSince1970: 1000),
            feishuConfigName: "测试",
            total: 1
        )
        log.finishedAt = Date(timeIntervalSince1970: 1332)

        #expect(log.durationSeconds == 332)
    }

    @Test("durationFormatted 格式化正确")
    func durationFormatted() {
        var log = ExecutionLog(
            startedAt: Date(timeIntervalSince1970: 0),
            feishuConfigName: "测试",
            total: 1
        )
        log.finishedAt = Date(timeIntervalSince1970: 332)

        #expect(log.durationFormatted == "5m32s")
    }

    @Test("未完成时 durationFormatted 返回 -")
    func durationUnfinished() {
        let log = ExecutionLog(feishuConfigName: "测试", total: 1)
        #expect(log.durationFormatted == "-")
    }

    @Test("Codable 编解码")
    func codable() throws {
        var log = ExecutionLog(feishuConfigName: "编码测试", total: 3)
        log.addEntry(level: .info, message: "日志1")
        log.addEntry(level: .error, message: "日志2")
        log.successCount = 2
        log.failedCount = 1
        log.finishedAt = Date()

        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(ExecutionLog.self, from: data)

        #expect(decoded.feishuConfigName == "编码测试")
        #expect(decoded.total == 3)
        #expect(decoded.successCount == 2)
        #expect(decoded.failedCount == 1)
        #expect(decoded.entries.count == 2)
        #expect(decoded.finishedAt != nil)
    }
}

@Suite("LogEntry 测试")
struct LogEntryTests {

    @Test("默认值初始化")
    func defaultInit() {
        let entry = LogEntry(level: .info, message: "测试消息")
        #expect(entry.level == .info)
        #expect(entry.message == "测试消息")
        #expect(entry.taskIndex == nil)
        #expect(entry.taskType == nil)
        #expect(entry.account == nil)
    }

    @Test("完整初始化")
    func fullInit() {
        let entry = LogEntry(
            level: .success,
            message: "发布成功",
            taskIndex: 3,
            taskType: "video",
            account: "dyfx750"
        )
        #expect(entry.taskIndex == 3)
        #expect(entry.taskType == "video")
        #expect(entry.account == "dyfx750")
    }

    @Test("LogLevel rawValue")
    func logLevelRawValue() {
        #expect(LogLevel.info.rawValue == "info")
        #expect(LogLevel.success.rawValue == "success")
        #expect(LogLevel.error.rawValue == "error")
        #expect(LogLevel.warning.rawValue == "warning")
    }
}
