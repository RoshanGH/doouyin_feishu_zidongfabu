import Foundation

/// LogStore 相关错误
enum LogStoreError: LocalizedError {
    case directoryCreationFailed(Error)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case writeFailed(Error)
    case readFailed(Error)
    case logNotFound(UUID)
    case exportFailed(Error)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let error):
            return "无法创建日志目录：\(error.localizedDescription)"
        case .encodingFailed(let error):
            return "日志序列化失败：\(error.localizedDescription)"
        case .decodingFailed(let error):
            return "日志解析失败：\(error.localizedDescription)"
        case .writeFailed(let error):
            return "写入日志文件失败：\(error.localizedDescription)"
        case .readFailed(let error):
            return "读取日志文件失败：\(error.localizedDescription)"
        case .logNotFound(let id):
            return "找不到 ID 为 \(id) 的日志"
        case .exportFailed(let error):
            return "导出日志失败：\(error.localizedDescription)"
        }
    }
}

/// 执行日志的持久化存储
/// 存储路径: ~/Library/Application Support/com.menggang.douyin-uploader/logs/
final class LogStore {

    // MARK: - 路径

    private static let appBundleId = "com.menggang.douyin-uploader"

    static func logsDirectory() -> URL {
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fallback
        return appSupport
            .appendingPathComponent(appBundleId, isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    // MARK: - 实例

    private let logsDir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter logsDirectory: 自定义日志目录（nil 时使用默认路径，方便测试注入）
    init(logsDirectory: URL? = nil) {
        self.logsDir = logsDirectory ?? LogStore.logsDirectory()

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - 目录初始化

    private func ensureDirectoryExists() throws {
        guard !FileManager.default.fileExists(atPath: logsDir.path) else { return }
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw LogStoreError.directoryCreationFailed(error)
        }
    }

    // MARK: - 文件名

    private func fileName(for log: ExecutionLog) -> String {
        let ts = ISO8601DateFormatter().string(from: log.startedAt)
            .replacingOccurrences(of: ":", with: "-")
        return "\(ts)_\(log.id.uuidString).json"
    }

    private func fileURL(for log: ExecutionLog) -> URL {
        logsDir.appendingPathComponent(fileName(for: log))
    }

    private func fileURL(for id: UUID) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil) else {
            return nil
        }
        return files.first { $0.lastPathComponent.contains(id.uuidString) }
    }

    // MARK: - 保存

    /// 保存单条执行日志
    /// - Parameter log: 执行日志
    /// - Throws: LogStoreError
    func saveLog(_ log: ExecutionLog) throws {
        try ensureDirectoryExists()

        let data: Data
        do {
            data = try encoder.encode(log)
        } catch {
            throw LogStoreError.encodingFailed(error)
        }

        do {
            try data.write(to: fileURL(for: log), options: .atomic)
        } catch {
            throw LogStoreError.writeFailed(error)
        }
    }

    // MARK: - 读取

    /// 读取所有日志（仅摘要，entries 为空以节省内存）
    /// - Returns: 按时间倒序排列的日志摘要列表
    func loadAll() -> [ExecutionLog] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logsDir,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let logs: [ExecutionLog] = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      var log = try? decoder.decode(ExecutionLog.self, from: data)
                else { return nil }
                // 仅保留摘要，清空 entries 节省内存
                log.entries = []
                return log
            }
            .sorted { $0.startedAt > $1.startedAt }

        return logs
    }

    /// 读取单条完整日志（含 entries）
    /// - Parameter id: 日志 ID
    /// - Returns: 找不到时返回 nil
    func loadLog(id: UUID) -> ExecutionLog? {
        guard let url = fileURL(for: id),
              let data = try? Data(contentsOf: url),
              let log = try? decoder.decode(ExecutionLog.self, from: data)
        else { return nil }
        return log
    }

    // MARK: - 清理

    /// 删除超过 retentionDays 天的日志
    /// - Parameter retentionDays: 保留天数
    func cleanup(retentionDays: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logsDir,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Date()
        ) ?? Date()

        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let log = try? decoder.decode(ExecutionLog.self, from: data)
            else { continue }

            if log.startedAt < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// 删除指定 ID 的日志
    /// - Parameter id: 日志 ID
    func deleteLog(id: UUID) {
        guard let url = fileURL(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 导出（脱敏）

    /// 导出日志为脱敏的 .txt 文件，写入临时目录
    /// - Parameter log: 要导出的日志（含完整 entries）
    /// - Returns: 导出文件 URL
    /// - Throws: LogStoreError
    func exportLog(_ log: ExecutionLog) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = []
        lines.append("========== 执行日志导出 ==========")
        lines.append("配置名称：\(log.feishuConfigName)")
        lines.append("开始时间：\(formatter.string(from: log.startedAt))")
        if let finishedAt = log.finishedAt {
            lines.append("结束时间：\(formatter.string(from: finishedAt))")
            lines.append("耗时：\(log.durationFormatted)")
        }
        lines.append("总任务数：\(log.total)")
        lines.append("成功：\(log.successCount)  失败：\(log.failedCount)")
        lines.append("==================================")
        lines.append("")

        for entry in log.entries {
            let time = formatter.string(from: entry.timestamp)
            let level = entry.level.rawValue.uppercased()
            let message = desensitize(entry.message)
            var line = "[\(time)] [\(level)] \(message)"
            if let account = entry.account {
                line += "  (账号: \(account))"
            }
            lines.append(line)
        }

        let content = lines.joined(separator: "\n")
        let data = Data(content.utf8)

        let tmpDir = FileManager.default.temporaryDirectory
        let dateStr = ISO8601DateFormatter().string(from: log.startedAt)
            .replacingOccurrences(of: ":", with: "-")
        let exportURL = tmpDir.appendingPathComponent("log_\(dateStr).txt")

        do {
            try data.write(to: exportURL, options: .atomic)
        } catch {
            throw LogStoreError.exportFailed(error)
        }

        return exportURL
    }

    // MARK: - 脱敏处理

    /// 对字符串中的敏感信息进行脱敏（Cookie/PAT/Token 只保留前4位 + ***）
    private func desensitize(_ text: String) -> String {
        // 匹配常见 cookie 值模式（key=value; 或 key=value$）
        var result = text

        // 替换 Bearer token
        result = replaceSensitivePattern(
            in: result,
            pattern: #"(Bearer\s+)([A-Za-z0-9\-_\.]{4})[A-Za-z0-9\-_\.]+"#,
            replacement: "$1$2***"
        )

        // 替换长随机字符串（cookie 值等，超过8位的连续字母数字串）
        result = replaceSensitivePattern(
            in: result,
            pattern: #"(=)([A-Za-z0-9\-_]{4})[A-Za-z0-9\-_]{4,}"#,
            replacement: "$1$2***"
        )

        return result
    }

    private func replaceSensitivePattern(in text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}
