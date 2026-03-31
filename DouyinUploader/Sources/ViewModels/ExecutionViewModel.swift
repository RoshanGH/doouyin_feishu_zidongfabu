import Foundation
import SwiftUI

// MARK: - 飞书记录解析工具

/// 将飞书 record 列表解析为 PublishTask 数组
private func parseTasksFromRecords(_ records: [FeishuRecord]) -> [PublishTask] {
    return records.compactMap { record in
        parseTask(from: record)
    }
}

/// 将单条飞书 record 解析为 PublishTask
private func parseTask(from record: FeishuRecord) -> PublishTask? {
    let fields = record.fields

    // 抖音账号（必填）
    guard let accountRaw = fields[FeishuColumn.douyinAccount],
          let douyinAccountId = extractTextValue(accountRaw) else {
        return nil
    }

    // 作品文案（必填）
    let contentRaw = fields[FeishuColumn.content]
    let content = contentRaw.flatMap { extractTextValue($0) } ?? ""

    // 作品标题（图文专用，可为空）
    let titleRaw = fields[FeishuColumn.title]
    let title = titleRaw.flatMap { extractTextValue($0) }

    // 话题标签（逗号分隔字符串）
    let tagsRaw = fields[FeishuColumn.tags]
    let tagString = tagsRaw.flatMap { extractTextValue($0) }
    let tags = parseTags(tagString)

    // 抖音名称（可选）
    let douyinNameRaw = fields[FeishuColumn.douyinName]
    let douyinName = douyinNameRaw.flatMap { extractTextValue($0) }

    // 音乐名称（可选）
    let musicNameRaw = fields[FeishuColumn.musicName]
    let musicName = musicNameRaw.flatMap { extractTextValue($0) }

    // 素材附件
    let attachments = extractAttachments(fields[FeishuColumn.material])

    // 定时发布时间
    let scheduledTimeRaw = fields[FeishuColumn.scheduledTime]
    let scheduledTime = extractDate(scheduledTimeRaw)
    print("[Parse] 定时发布原始值: \(String(describing: scheduledTimeRaw)), type: \(type(of: scheduledTimeRaw)), 解析结果: \(String(describing: scheduledTime))")

    // 发布状态
    let statusRaw = fields[FeishuColumn.status]
    let statusText = statusRaw.flatMap { extractTextValue($0) } ?? ""
    let status = PublishStatus(rawValue: statusText) ?? .allowPublish

    return PublishTask(
        recordId: record.recordId,
        douyinAccountId: douyinAccountId,
        douyinName: douyinName?.isEmpty == true ? nil : douyinName,
        attachments: attachments,
        title: title?.isEmpty == true ? nil : title,
        content: content,
        tags: tags,
        musicName: musicName?.isEmpty == true ? nil : musicName,
        scheduledTime: scheduledTime,
        status: status
    )
}

/// 从飞书字段值中提取文本
private func extractTextValue(_ value: Any) -> String? {
    // 直接字符串
    if let str = value as? String, !str.isEmpty {
        return str
    }
    // 富文本数组格式：[{"type": "text", "text": "内容"}]
    if let arr = value as? [[String: Any]] {
        let text = arr.compactMap { item -> String? in
            item["text"] as? String
        }.joined()
        return text.isEmpty ? nil : text
    }
    return nil
}

/// 从飞书字段值中提取附件列表
private func extractAttachments(_ value: Any?) -> [FeishuAttachment] {
    guard let arr = value as? [[String: Any]] else { return [] }
    return arr.compactMap { item -> FeishuAttachment? in
        guard let fileToken = item["file_token"] as? String,
              let name = item["name"] as? String,
              let type_ = item["type"] as? String,
              let size = item["size"] as? Int else {
            return nil
        }
        return FeishuAttachment(
            fileToken: fileToken,
            name: name,
            type: type_,
            size: size,
            url: item["url"] as? String
        )
    }
}

/// 从飞书字段值中提取日期（飞书时间戳为毫秒）
private func extractDate(_ value: Any?) -> Date? {
    guard let value else { return nil }

    // 飞书日期字段：毫秒时间戳（数字类型）
    if let ms = value as? Double {
        return Date(timeIntervalSince1970: ms / 1000)
    }
    if let ms = value as? Int {
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    // 飞书文本字段：字符串格式 "2026-03-29 17:45" 或 "2026-03-29T17:45:00"
    if let str = value as? String, !str.isEmpty {
        let formatters: [String] = [
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss",
        ]
        for format in formatters {
            let fmt = DateFormatter()
            fmt.dateFormat = format
            fmt.locale = Locale(identifier: "zh_CN")
            if let date = fmt.date(from: str) {
                return date
            }
        }
    }

    return nil
}

// MARK: - ExecutionViewModel

/// 执行发布页面的核心 ViewModel
/// 负责：读取飞书任务、校验、串行执行发布、实时日志、状态管理
@MainActor
final class ExecutionViewModel: ObservableObject {

    // MARK: - 状态机

    /// 执行状态枚举
    enum ExecutionState: Equatable {
        case idle                    // 初始状态，等待选择配置
        case loading                 // 正在读取飞书任务
        case loadFailed(String)      // 读取失败（含错误信息）
        case noTasks                 // 没有待执行任务
        case overview                // 任务概览（等待用户确认执行）
        case running                 // 执行中
        case paused                  // 已暂停
        case networkError            // 网络错误（执行中断）
        case completed               // 执行完成

        static func == (lhs: ExecutionState, rhs: ExecutionState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.loading, .loading): return true
            case (.loadFailed(let a), .loadFailed(let b)): return a == b
            case (.noTasks, .noTasks): return true
            case (.overview, .overview): return true
            case (.running, .running): return true
            case (.paused, .paused): return true
            case (.networkError, .networkError): return true
            case (.completed, .completed): return true
            default: return false
            }
        }
    }

    // MARK: - Published 属性

    /// 当前执行状态
    @Published var state: ExecutionState = .idle

    /// 当前选择的飞书配置 ID
    @Published var selectedConfigId: UUID?

    /// 所有已解析的任务（包括校验失败的）
    @Published var tasks: [PublishTask] = []

    /// 校验通过的任务
    @Published var validTasks: [PublishTask] = []

    /// 校验失败的任务
    @Published var invalidTasks: [PublishTask] = []

    /// 实时日志条目
    @Published var logs: [LogEntry] = []

    /// 成功发布数量
    @Published var successCount = 0

    /// 失败发布数量
    @Published var failedCount = 0

    /// 当前正在执行的任务索引（基于 validTasks）
    @Published var currentTaskIndex = 0

    /// 本次执行的完整日志记录
    @Published var executionLog: ExecutionLog?

    /// 执行开始时间
    @Published var startTime: Date?

    // MARK: - 账号登录状态

    /// 任务涉及的全部抖音号
    @Published var requiredAccounts: [String] = []

    /// 已登录的抖音号集合
    @Published var loggedInAccounts: Set<String> = []

    /// Cookie 已过期的抖音号集合
    @Published var expiredAccounts: Set<String> = []

    /// 账号 ID → 昵称 映射
    @Published var accountNicknames: [String: String] = [:]

    // MARK: - 可用配置列表

    /// 所有飞书配置（供 Picker 使用）
    @Published var configs: [FeishuConfig] = []

    // MARK: - 依赖

    private let configStore: ConfigStore
    private let accountStore: AccountStore
    private let cookieManager: DouyinCookieManager
    private let publishService: DouyinPublishServiceProtocol
    private let logStore: LogStore
    /// 每次执行时重新创建（确保读取最新 settings，包括 AI 配置）
    private func createPublishService() -> CDPPublishService {
        let svc = CDPPublishService(cookieManager: cookieManager, settings: SettingsManager().load())
        svc.onLog = { [weak self] level, message in
            Task { @MainActor in
                self?.addLog(level: level, message: message)
            }
        }
        return svc
    }

    /// 当前执行 Task（用于取消）
    private var executionTask: Task<Void, Never>?

    /// 暂停标志（每条任务执行前检查）
    private var isPaused = false

    /// 任务间等待的最小秒数
    private let minIntervalSec: Double = 5
    /// 任务间等待的最大秒数
    private let maxIntervalSec: Double = 15

    // MARK: - 初始化

    init(
        configStore: ConfigStore = ConfigStore(),
        accountStore: AccountStore = AccountStore(),
        cookieManager: DouyinCookieManager = DouyinCookieManager(),
        publishService: DouyinPublishServiceProtocol = DouyinPublishService(),
        logStore: LogStore = LogStore()
    ) {
        self.configStore = configStore
        self.accountStore = accountStore
        self.cookieManager = cookieManager
        self.publishService = publishService
        self.logStore = logStore
        loadConfigs()
    }

    // MARK: - 加载配置列表

    /// 从磁盘加载所有飞书配置
    func loadConfigs() {
        do {
            configs = try configStore.load()
            // 恢复上次选择的配置
            if selectedConfigId == nil {
                if let lastId = UserDefaults.standard.string(forKey: "lastSelectedConfigId"),
                   let uuid = UUID(uuidString: lastId),
                   configs.contains(where: { $0.id == uuid }) {
                    selectedConfigId = uuid
                } else {
                    selectedConfigId = configs.first?.id
                }
            }
        } catch {
            // 配置加载失败不阻断主流程
        }
    }

    // MARK: - 读取飞书任务

    /// 读取飞书待发布任务，解析、校验并分组
    func loadTasks() async {
        guard let configId = selectedConfigId,
              let config = configs.first(where: { $0.id == configId }) else {
            state = .loadFailed("请先选择一个飞书配置")
            return
        }

        // 记住选择的配置
        UserDefaults.standard.set(configId.uuidString, forKey: "lastSelectedConfigId")

        state = .loading
        logs = []
        tasks = []
        validTasks = []
        invalidTasks = []
        successCount = 0
        failedCount = 0
        currentTaskIndex = 0

        addLog(level: .info, message: "开始读取飞书任务，配置：\(config.name)")

        do {
            let api = FeishuAPI(config: config)
            let records = try await api.fetchRecords()

            addLog(level: .info, message: "共获取 \(records.count) 条记录（飞书返回）")

            // 解析 record 为 PublishTask
            let parsedTasks = parseTasksFromRecords(records)

            // 二次过滤：只保留状态为 允许发布 / 发布失败 / 发布中 的任务
            // （飞书 filter 可能未精确生效，在客户端再过滤一次确保准确）
            let allowedStatuses: Set<PublishStatus> = [.allowPublish, .publishFailed, .publishing]
            let allTasks = parsedTasks.filter { allowedStatuses.contains($0.status) }

            // 日志：显示每条记录的状态，便于排查
            for (i, task) in parsedTasks.enumerated() {
                let scheduleInfo = task.scheduledTime != nil ? ", 定时=\(task.scheduledTime!)" : ""
                addLog(level: .info, message: "  记录\(i+1): 账号=\(task.douyinAccountId), 状态=\(task.status.rawValue), 文案=\(task.content.prefix(15))\(scheduleInfo)...")
            }

            if parsedTasks.count != allTasks.count {
                addLog(level: .info, message: "过滤后保留 \(allTasks.count) 条待发布任务（排除 \(parsedTasks.count - allTasks.count) 条非待发布状态）")
            }

            tasks = allTasks

            // 按校验结果分组
            var valid: [PublishTask] = []
            var invalid: [PublishTask] = []

            for task in allTasks {
                if !task.isValid {
                    invalid.append(task)
                    addLog(
                        level: .warning,
                        message: "任务校验失败（\(task.douyinAccountId)）：\(invalidReason(task))"
                    )
                } else if task.isScheduleExpired {
                    // 定时时间已过期的任务也标记为无效
                    var failedTask = task
                    failedTask.failureReason = "定时发布时间已过期"
                    invalid.append(failedTask)
                    addLog(
                        level: .warning,
                        message: "任务定时时间已过期（\(task.douyinAccountId)），跳过"
                    )
                } else {
                    valid.append(task)
                }
            }

            validTasks = valid
            invalidTasks = invalid

            if allTasks.isEmpty {
                state = .noTasks
                addLog(level: .info, message: "没有待发布的任务")
                return
            }

            addLog(level: .info, message: "有效任务：\(valid.count)，无效任务：\(invalid.count)")

            // 统计涉及的抖音号，检查登录状态
            await checkAccountLoginStatus(for: valid)

            state = .overview

        } catch {
            let errMsg = error.localizedDescription
            addLog(level: .error, message: "读取任务失败：\(errMsg)")
            state = .loadFailed(errMsg)
        }
    }

    // MARK: - 账号登录状态检测

    /// 检测所有涉及账号的 Cookie 有效性（请求抖音接口验证，和账号管理页逻辑一致）
    private func checkAccountLoginStatus(for tasks: [PublishTask]) async {
        let accountIds = Array(Set(tasks.map { $0.douyinAccountId })).sorted()
        requiredAccounts = accountIds

        // 从任务中提取账号昵称
        var nicknames: [String: String] = [:]
        for task in tasks {
            if let name = task.douyinName, !name.isEmpty {
                nicknames[task.douyinAccountId] = name
            }
        }
        accountNicknames = nicknames

        let loginService = DouyinLoginService()
        var loggedIn: Set<String> = []
        var expired: Set<String> = []

        addLog(level: .info, message: "正在验证账号登录状态...")

        for accountId in accountIds {
            let nickname = nicknames[accountId] ?? accountId
            addLog(level: .info, message: "  检测账号 \(nickname)...")
            let isValid = await loginService.validateCookies(uniqueId: accountId)
            if isValid {
                loggedIn.insert(accountId)
                addLog(level: .info, message: "  账号 \(nickname): ✅ 登录有效")
            } else {
                expired.insert(accountId)
                addLog(level: .warning, message: "  账号 \(nickname): ❌ 登录已过期，请重新扫码")
            }
        }

        loggedInAccounts = loggedIn
        expiredAccounts = expired
    }

    /// 重新检查登录状态（用户在账号管理页扫码后回来点击）
    func recheckLoginStatus() async {
        await checkAccountLoginStatus(for: validTasks)
    }

    // MARK: - 开始执行

    /// 开始串行执行所有有效任务
    func startExecution() {
        guard !validTasks.isEmpty else { return }

        // 网络检查
        if !NetworkMonitor().isConnected {
            addLog(level: .error, message: "网络不可用，请检查网络连接后重试")
            state = .networkError
            return
        }

        guard let configId = selectedConfigId,
              let config = configs.first(where: { $0.id == configId }) else {
            return
        }

        // Chrome 未安装时自动下载
        if !ChromeManager.shared.isInstalled {
            state = .running
            addLog(level: .info, message: "首次运行，正在下载 Chrome 浏览器引擎...")

            ChromeManager.shared.onDownloadProgress = { [weak self] progress, message in
                Task { @MainActor in
                    self?.addLog(level: .info, message: "下载进度: \(Int(progress * 100))% — \(message)")
                }
            }

            Task {
                do {
                    try await ChromeManager.shared.downloadIfNeeded()
                    await MainActor.run {
                        self.addLog(level: .success, message: "Chrome 下载完成，开始执行任务...")
                        self.doStartExecution(config: config)
                    }
                } catch {
                    await MainActor.run {
                        self.addLog(level: .error, message: "Chrome 下载失败：\(error.localizedDescription)")
                        self.state = .loadFailed("Chrome 下载失败：\(error.localizedDescription)")
                    }
                }
            }
            return
        }

        doStartExecution(config: config)
    }

    private func doStartExecution(config: FeishuConfig) {
        state = .running
        isPaused = false
        currentTaskIndex = 0
        successCount = 0
        failedCount = 0
        startTime = Date()

        // 初始化执行日志
        var log = ExecutionLog(
            feishuConfigName: config.name,
            total: validTasks.count
        )
        executionLog = log

        addLog(level: .info, message: "=== 开始执行，共 \(validTasks.count) 条任务 ===")

        let cdpPublishService = createPublishService()

        executionTask = Task {
            // 按账号分组（同一账号的任务在一个浏览器中完成）
            var tasksByAccount: [(accountId: String, tasks: [PublishTask])] = []
            var seen: [String: Int] = [:]
            for task in validTasks {
                if let idx = seen[task.douyinAccountId] {
                    tasksByAccount[idx].tasks.append(task)
                } else {
                    seen[task.douyinAccountId] = tasksByAccount.count
                    tasksByAccount.append((task.douyinAccountId, [task]))
                }
            }

            var globalIndex = 0

            for group in tasksByAccount {
                if Task.isCancelled { break }

                addLog(level: .info, message: "--- 开始处理账号: \(group.accountId)（\(group.tasks.count) 条任务）---")

                // 按批量上限切分（防风控）
                let currentSettings = SettingsManager().load()
                let batchLimit = max(1, currentSettings.batchLimit)
                let batches = stride(from: 0, to: group.tasks.count, by: batchLimit).map {
                    Array(group.tasks[$0..<min($0 + batchLimit, group.tasks.count)])
                }

                for (batchIndex, batchTasks) in batches.enumerated() {
                    if Task.isCancelled { break }

                    if batches.count > 1 {
                        addLog(level: .info, message: "  批次 \(batchIndex + 1)/\(batches.count)（\(batchTasks.count) 条）")
                    }

                    // 非第一批需要等待
                    if batchIndex > 0 {
                        let waitMinutes = currentSettings.batchWaitMinutes
                        addLog(level: .info, message: "  达到单账号批量上限（\(batchLimit) 条），等待 \(waitMinutes) 分钟后继续...")
                        try? await Task.sleep(nanoseconds: UInt64(waitMinutes) * 60 * 1_000_000_000)
                    }

                await cdpPublishService.publishBatch(
                    accountId: group.accountId,
                    tasks: batchTasks,
                    downloadFiles: { [weak self] task in
                        guard let self else { throw FeishuAPIError.invalidResponse("ViewModel 已释放") }

                        // 暂停检查
                        while self.isPaused {
                            if Task.isCancelled { throw CancellationError() }
                            try await Task.sleep(nanoseconds: 500_000_000)
                        }

                        self.currentTaskIndex = globalIndex
                        globalIndex += 1

                        // 回写"发布中"
                        await self.updateFeishu(task: task, status: .publishing, reason: nil)

                        guard let configId = self.selectedConfigId,
                              let cfg = self.configs.first(where: { $0.id == configId }) else {
                            throw FeishuAPIError.invalidResponse("配置不存在")
                        }
                        let api = FeishuAPI(config: cfg)

                        self.addLog(level: .info, message: "下载素材（共 \(task.attachments.count) 个）...", account: task.douyinAccountId)

                        var localFiles: [URL] = []
                        for (i, att) in task.attachments.enumerated() {
                            let fileName = "\(task.recordId)_\(i)_\(att.name)"
                            let fileURL = try await api.downloadAttachment(fileToken: att.fileToken, fileName: fileName)
                            localFiles.append(fileURL)
                            self.addLog(level: .info, message: "素材 \(i + 1)/\(task.attachments.count) 下载完成", account: task.douyinAccountId)
                        }
                        return localFiles
                    },
                    onTaskResult: { [weak self] task, result in
                        guard let self else { return }

                        switch result {
                        case .success(let publishResult):
                            if publishResult.success {
                                self.addLog(level: .success, message: "发布成功！", taskType: task.isVideo ? "video" : "image", account: task.douyinAccountId)
                                self.successCount += 1
                                await self.updateFeishu(task: task, status: .published, reason: nil)
                            } else {
                                self.addLog(level: .error, message: "发布失败：\(publishResult.message)", account: task.douyinAccountId)
                                self.failedCount += 1
                                await self.updateFeishu(task: task, status: .publishFailed, reason: publishResult.message)
                            }
                        case .failure(let error):
                            self.addLog(level: .error, message: "发布异常：\(error.localizedDescription)", account: task.douyinAccountId)
                            self.failedCount += 1
                            await self.updateFeishu(task: task, status: .publishFailed, reason: error.localizedDescription)
                        }

                        log.successCount = self.successCount
                        log.failedCount = self.failedCount
                        self.executionLog = log
                    }
                )
                } // batches 循环
            } // tasksByAccount 循环

            // 执行完成
            if !Task.isCancelled {
                var finalLog = log
                finalLog.finishedAt = Date()
                finalLog.successCount = successCount
                finalLog.failedCount = failedCount
                executionLog = finalLog

                addLog(
                    level: .success,
                    message: "=== 执行完成：成功 \(successCount)，失败 \(failedCount)，耗时 \(finalLog.durationFormatted) ==="
                )
                saveExecutionLog()
                state = .completed

                // 系统通知
                NotificationService.shared.sendExecutionComplete(success: successCount, failed: failedCount)
            }
        }
    }

    // MARK: - 暂停 / 继续 / 停止

    /// 暂停执行（当前任务执行完后暂停）
    func pauseExecution() {
        isPaused = true
        state = .paused
        addLog(level: .warning, message: "执行已暂停，当前任务完成后停止")
    }

    /// 继续执行
    func resumeExecution() {
        isPaused = false
        state = .running
        addLog(level: .info, message: "继续执行...")
    }

    /// 停止执行（强制取消）
    func stopExecution() {
        executionTask?.cancel()
        executionTask = nil
        isPaused = false

        var finalLog = executionLog
        finalLog?.finishedAt = Date()
        finalLog?.successCount = successCount
        finalLog?.failedCount = failedCount
        executionLog = finalLog

        addLog(level: .warning, message: "=== 执行已中止：成功 \(successCount)，失败 \(failedCount) ===")
        saveExecutionLog()
        state = .completed
    }

    // MARK: - 重置到初始状态

    /// 重置 ViewModel 回到 idle 状态，可重新选择配置并拉取任务
    /// 重新执行失败项（回到概览页，只保留上次失败的任务）
    func retryFailedTasks() {
        guard selectedConfigId != nil else {
            reset()
            return
        }

        // 重新拉取飞书任务（飞书中"发布失败"的会被筛选出来）
        executionTask?.cancel()
        executionTask = nil
        isPaused = false
        logs = []
        successCount = 0
        failedCount = 0
        currentTaskIndex = 0
        executionLog = nil
        startTime = nil
        state = .loading

        Task {
            await loadTasks()
        }
    }

    func reset() {
        executionTask?.cancel()
        executionTask = nil
        isPaused = false
        state = .idle
        tasks = []
        validTasks = []
        invalidTasks = []
        logs = []
        successCount = 0
        failedCount = 0
        currentTaskIndex = 0
        executionLog = nil
        startTime = nil
        requiredAccounts = []
        loggedInAccounts = []
        expiredAccounts = []
        accountNicknames = [:]
    }

    // MARK: - 内部：执行单条任务

    /// 执行单条发布任务的完整流程
    private func executeTask(_ task: PublishTask, index: Int) async {
        let taskType = task.isVideo ? "视频" : "图文"
        let account = task.douyinAccountId

        addLog(
            level: .info,
            message: "[\(index + 1)/\(validTasks.count)] 开始执行：\(account) | \(taskType)",
            taskIndex: index,
            taskType: task.isVideo ? "video" : "image",
            account: account
        )

        // 回写飞书状态：发布中
        await updateFeishu(
            task: task,
            status: .publishing,
            reason: nil
        )

        // 下载素材
        var localFiles: [URL] = []
        do {
            guard let configId = selectedConfigId,
                  let config = configs.first(where: { $0.id == configId }) else {
                throw FeishuAPIError.invalidResponse("配置不存在")
            }
            let api = FeishuAPI(config: config)

            addLog(level: .info, message: "下载素材（共 \(task.attachments.count) 个）...", taskIndex: index, account: account)

            for (i, attachment) in task.attachments.enumerated() {
                let fileName = "\(task.recordId)_\(i)_\(attachment.name)"
                let fileURL = try await api.downloadAttachment(fileToken: attachment.fileToken, fileName: fileName)
                localFiles.append(fileURL)
                addLog(level: .info, message: "素材 \(i + 1)/\(task.attachments.count) 下载完成", taskIndex: index, account: account)
            }
        } catch {
            let reason = "下载素材失败：\(error.localizedDescription)"
            addLog(level: .error, message: reason, taskIndex: index, account: account)
            failedCount += 1

            await updateFeishu(task: task, status: .publishFailed, reason: reason)
            cleanupLocalFiles(localFiles)
            return
        }

        // 调用发布服务
        do {
            if task.hasMusic {
                addLog(level: .info, message: "搜索音乐「\(task.musicName ?? "")」", taskIndex: index, account: account)
            }
            addLog(level: .info, message: "正在发布到抖音（CDP）...", taskIndex: index, account: account)
            let svc = createPublishService()
            let result = try await svc.publishTask(task: task, localFiles: localFiles)

            if result.success {
                addLog(
                    level: .success,
                    message: "发布成功！\(result.message)",
                    taskIndex: index,
                    taskType: task.isVideo ? "video" : "image",
                    account: account
                )
                successCount += 1
                await updateFeishu(task: task, status: .published, reason: nil)
            } else {
                let reason = "发布失败：\(result.message)"
                addLog(level: .error, message: reason, taskIndex: index, account: account)
                failedCount += 1
                await updateFeishu(task: task, status: .publishFailed, reason: result.message)
            }
        } catch {
            let reason = error.localizedDescription
            addLog(level: .error, message: "发布异常：\(reason)", taskIndex: index, account: account)
            failedCount += 1
            await updateFeishu(task: task, status: .publishFailed, reason: reason)
        }

        // 清理临时文件
        cleanupLocalFiles(localFiles)
    }

    // MARK: - 回写飞书

    /// 将任务状态回写到飞书表格
    private func updateFeishu(
        task: PublishTask,
        status: PublishStatus,
        reason: String?
    ) async {
        guard let configId = selectedConfigId,
              let config = configs.first(where: { $0.id == configId }) else {
            return
        }

        var fields: [String: Any] = [
            FeishuColumn.status: status.rawValue
        ]

        if status == .published {
            // 记录发布时间：先尝试毫秒时间戳（日期字段），失败则用字符串（文本字段）
            fields[FeishuColumn.publishTime] = Int(Date().timeIntervalSince1970 * 1000)
        }

        if let reason {
            fields[FeishuColumn.failureReason] = reason
        } else if status == .published {
            fields[FeishuColumn.failureReason] = ""
        }

        do {
            let api = FeishuAPI(config: config)
            try await api.updateRecord(recordId: task.recordId, fields: fields)
        } catch let error as FeishuAPIError {
            // 如果是字段类型转换错误，用字符串格式重试
            if case .apiError(let code, _) = error, code == 1254060 {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let timeStr = formatter.string(from: Date())

                var retryFields = fields
                retryFields[FeishuColumn.publishTime] = timeStr

                do {
                    let api = FeishuAPI(config: config)
                    try await api.updateRecord(recordId: task.recordId, fields: retryFields)
                    return // 重试成功
                } catch {
                    // 重试也失败，记录警告
                }
            }
            // 非类型错误或重试也失败
        } catch {
            addLog(
                level: .warning,
                message: "回写飞书失败（\(task.douyinAccountId)）：\(error.localizedDescription)"
            )
        }
    }

    // MARK: - 保存执行日志

    /// 将当前执行日志持久化到磁盘
    func saveExecutionLog() {
        guard let log = executionLog else { return }
        do {
            try logStore.saveLog(log)
        } catch {
            addLog(level: .warning, message: "保存执行日志失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 追加日志

    /// 向日志列表追加一条记录（同时追加到 executionLog）
    func addLog(
        level: LogLevel,
        message: String,
        taskIndex: Int? = nil,
        taskType: String? = nil,
        account: String? = nil
    ) {
        let entry = LogEntry(
            level: level,
            message: message,
            taskIndex: taskIndex,
            taskType: taskType,
            account: account
        )
        logs.append(entry)
        executionLog?.entries.append(entry)

        // 同步写入调试日志文件
        let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
        let line = "[\(timestamp)] [\(level.rawValue)] \(message)\n"
        let debugLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("douyin_debug.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugLogURL.path) {
                if let handle = try? FileHandle(forWritingTo: debugLogURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: debugLogURL)
            }
        }
    }

    // MARK: - 辅助方法

    /// 获取任务校验失败的原因描述
    private func invalidReason(_ task: PublishTask) -> String {
        switch task.mediaValidation {
        case .invalid(let reason): return reason
        default: return "未知原因"
        }
    }

    /// 清理本地临时文件
    private func cleanupLocalFiles(_ files: [URL]) {
        for fileURL in files {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - 计算属性

    /// 是否全部账号都已登录（可以开始执行）
    var canStartExecution: Bool {
        guard !validTasks.isEmpty else { return false }
        return expiredAccounts.isEmpty
    }

    /// 执行进度（0.0 ~ 1.0）
    var progress: Double {
        guard !validTasks.isEmpty else { return 0 }
        let done = successCount + failedCount
        return Double(done) / Double(validTasks.count)
    }

    /// 剩余任务数
    var remainingCount: Int {
        validTasks.count - successCount - failedCount
    }

    /// 选中的配置对象
    var selectedConfig: FeishuConfig? {
        guard let id = selectedConfigId else { return nil }
        return configs.first { $0.id == id }
    }
}
