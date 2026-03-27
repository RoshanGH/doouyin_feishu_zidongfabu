import Foundation

/// 日志级别
enum LogLevel: String, Codable {
    case info
    case success
    case error
    case warning
}

/// 单条日志记录
struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    let taskIndex: Int?
    let taskType: String?      // "video" / "image"
    let account: String?       // 抖音号

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        message: String,
        taskIndex: Int? = nil,
        taskType: String? = nil,
        account: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.taskIndex = taskIndex
        self.taskType = taskType
        self.account = account
    }
}

/// 一次执行的完整日志
struct ExecutionLog: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    var finishedAt: Date?
    let feishuConfigName: String
    var total: Int
    var successCount: Int
    var failedCount: Int
    var entries: [LogEntry]

    var durationSeconds: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    var durationFormatted: String {
        guard let seconds = durationSeconds else { return "-" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m\(secs)s"
    }

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        feishuConfigName: String,
        total: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.feishuConfigName = feishuConfigName
        self.total = total
        self.successCount = 0
        self.failedCount = 0
        self.entries = []
    }

    mutating func addEntry(level: LogLevel, message: String, taskIndex: Int? = nil, taskType: String? = nil, account: String? = nil) {
        let entry = LogEntry(
            level: level,
            message: message,
            taskIndex: taskIndex,
            taskType: taskType,
            account: account
        )
        entries.append(entry)
    }
}
