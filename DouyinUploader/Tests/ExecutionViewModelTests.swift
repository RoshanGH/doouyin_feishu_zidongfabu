import XCTest
@testable import DouyinUploader

/// ExecutionViewModel 的单元测试
/// 只测试不涉及异步网络/WebView 操作的纯逻辑
final class ExecutionViewModelTests: XCTestCase {

    // MARK: - ExecutionState Equatable

    func testExecutionStateEquatable_idle() {
        let a = ExecutionViewModel.ExecutionState.idle
        let b = ExecutionViewModel.ExecutionState.idle
        XCTAssertEqual(a, b)
    }

    func testExecutionStateEquatable_loadFailed_sameMessage() {
        let a = ExecutionViewModel.ExecutionState.loadFailed("error msg")
        let b = ExecutionViewModel.ExecutionState.loadFailed("error msg")
        XCTAssertEqual(a, b)
    }

    func testExecutionStateEquatable_loadFailed_differentMessage() {
        let a = ExecutionViewModel.ExecutionState.loadFailed("err1")
        let b = ExecutionViewModel.ExecutionState.loadFailed("err2")
        XCTAssertNotEqual(a, b)
    }

    func testExecutionStateEquatable_different() {
        let running = ExecutionViewModel.ExecutionState.running
        let paused = ExecutionViewModel.ExecutionState.paused
        XCTAssertNotEqual(running, paused)
    }

    // MARK: - ViewModel 初始状态

    @MainActor
    func testInitialState_isIdle() {
        let vm = ExecutionViewModel()
        if case .idle = vm.state {
            // pass
        } else {
            XCTFail("初始状态应为 idle，实际为 \(vm.state)")
        }
    }

    @MainActor
    func testInitialState_emptyTasks() {
        let vm = ExecutionViewModel()
        XCTAssertTrue(vm.tasks.isEmpty)
        XCTAssertTrue(vm.validTasks.isEmpty)
        XCTAssertTrue(vm.invalidTasks.isEmpty)
    }

    @MainActor
    func testInitialState_countsAreZero() {
        let vm = ExecutionViewModel()
        XCTAssertEqual(vm.successCount, 0)
        XCTAssertEqual(vm.failedCount, 0)
        XCTAssertEqual(vm.currentTaskIndex, 0)
    }

    @MainActor
    func testInitialState_logsEmpty() {
        let vm = ExecutionViewModel()
        XCTAssertTrue(vm.logs.isEmpty)
    }

    // MARK: - 计算属性

    @MainActor
    func testProgress_emptyTasks_returnsZero() {
        let vm = ExecutionViewModel()
        XCTAssertEqual(vm.progress, 0.0)
    }

    @MainActor
    func testCanStartExecution_emptyValidTasks_returnsFalse() {
        let vm = ExecutionViewModel()
        // validTasks 为空时不可执行
        XCTAssertFalse(vm.canStartExecution)
    }

    @MainActor
    func testRemainingCount_initiallyZero() {
        let vm = ExecutionViewModel()
        XCTAssertEqual(vm.remainingCount, 0)
    }

    @MainActor
    func testSelectedConfig_noSelection_returnsNil() {
        let vm = ExecutionViewModel()
        vm.selectedConfigId = nil
        XCTAssertNil(vm.selectedConfig)
    }

    // MARK: - addLog 方法

    @MainActor
    func testAddLog_appendsToLogs() {
        let vm = ExecutionViewModel()
        vm.addLog(level: .info, message: "测试日志")
        XCTAssertEqual(vm.logs.count, 1)
        XCTAssertEqual(vm.logs[0].message, "测试日志")
        XCTAssertEqual(vm.logs[0].level, .info)
    }

    @MainActor
    func testAddLog_multipleEntries_preserveOrder() {
        let vm = ExecutionViewModel()
        vm.addLog(level: .info, message: "第一条")
        vm.addLog(level: .success, message: "第二条")
        vm.addLog(level: .error, message: "第三条")
        XCTAssertEqual(vm.logs.count, 3)
        XCTAssertEqual(vm.logs[0].message, "第一条")
        XCTAssertEqual(vm.logs[1].message, "第二条")
        XCTAssertEqual(vm.logs[2].message, "第三条")
    }

    @MainActor
    func testAddLog_withTaskIndexAndAccount() {
        let vm = ExecutionViewModel()
        vm.addLog(level: .warning, message: "警告信息", taskIndex: 3, taskType: "video", account: "testAccount")
        XCTAssertEqual(vm.logs[0].taskIndex, 3)
        XCTAssertEqual(vm.logs[0].taskType, "video")
        XCTAssertEqual(vm.logs[0].account, "testAccount")
    }

    @MainActor
    func testAddLog_appendsToExecutionLog_whenExists() {
        let vm = ExecutionViewModel()
        vm.executionLog = ExecutionLog(feishuConfigName: "测试配置", total: 5)
        vm.addLog(level: .info, message: "日志内容")

        XCTAssertEqual(vm.executionLog?.entries.count, 1)
        XCTAssertEqual(vm.executionLog?.entries[0].message, "日志内容")
    }

    // MARK: - reset 方法

    @MainActor
    func testReset_clearsAllState() {
        let vm = ExecutionViewModel()
        // 先设置一些状态
        vm.successCount = 3
        vm.failedCount = 1
        vm.addLog(level: .info, message: "一些日志")
        vm.state = .running

        // 执行重置
        vm.reset()

        // 验证所有状态已清空
        if case .idle = vm.state {
            // pass
        } else {
            XCTFail("reset 后状态应为 idle")
        }
        XCTAssertEqual(vm.successCount, 0)
        XCTAssertEqual(vm.failedCount, 0)
        XCTAssertTrue(vm.logs.isEmpty)
        XCTAssertTrue(vm.tasks.isEmpty)
        XCTAssertTrue(vm.validTasks.isEmpty)
        XCTAssertTrue(vm.invalidTasks.isEmpty)
        XCTAssertNil(vm.executionLog)
        XCTAssertNil(vm.startTime)
        XCTAssertTrue(vm.requiredAccounts.isEmpty)
        XCTAssertTrue(vm.loggedInAccounts.isEmpty)
        XCTAssertTrue(vm.expiredAccounts.isEmpty)
    }

    // MARK: - 飞书记录解析（通过 PublishTask 验证逻辑）

    func testPublishTask_validVideo_isVideoTrue() {
        let videoAttachment = FeishuAttachment(
            fileToken: "token1",
            name: "video.mp4",
            type: "video/mp4",
            size: 10000,
            url: nil
        )
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "account1",
            attachments: [videoAttachment],
            content: "测试内容"
        )
        XCTAssertTrue(task.isVideo)
        XCTAssertFalse(task.isImagePost)
        XCTAssertTrue(task.isValid)
    }

    func testPublishTask_validImages_isImagePostTrue() {
        let imageAttachments = [
            FeishuAttachment(fileToken: "token1", name: "img1.jpg", type: "image/jpeg", size: 1000, url: nil),
            FeishuAttachment(fileToken: "token2", name: "img2.png", type: "image/png", size: 2000, url: nil)
        ]
        let task = PublishTask(
            recordId: "rec2",
            douyinAccountId: "account2",
            attachments: imageAttachments,
            content: "图文内容"
        )
        XCTAssertFalse(task.isVideo)
        XCTAssertTrue(task.isImagePost)
        XCTAssertTrue(task.isValid)
    }

    func testPublishTask_emptyAttachments_isInvalid() {
        let task = PublishTask(
            recordId: "rec3",
            douyinAccountId: "account3",
            attachments: [],
            content: "无素材"
        )
        XCTAssertFalse(task.isVideo)
        XCTAssertFalse(task.isImagePost)
        XCTAssertFalse(task.isValid)
    }

    func testPublishTask_scheduleExpired() {
        let pastDate = Date().addingTimeInterval(-3600) // 1小时前
        let task = PublishTask(
            recordId: "rec4",
            douyinAccountId: "account4",
            attachments: [],
            content: "定时过期",
            scheduledTime: pastDate
        )
        XCTAssertTrue(task.isScheduleExpired)
    }

    func testPublishTask_scheduleFuture_notExpired() {
        let futureDate = Date().addingTimeInterval(3600) // 1小时后
        let task = PublishTask(
            recordId: "rec5",
            douyinAccountId: "account5",
            attachments: [],
            content: "定时未过期",
            scheduledTime: futureDate
        )
        XCTAssertFalse(task.isScheduleExpired)
    }

    // MARK: - 进度计算

    @MainActor
    func testProgress_withCompletedTasks() {
        let vm = ExecutionViewModel()
        // 手动模拟 validTasks（通过任务预览可以构造）
        let videoAttachment = FeishuAttachment(
            fileToken: "token1",
            name: "video.mp4",
            type: "video/mp4",
            size: 10000,
            url: nil
        )
        vm.validTasks = [
            PublishTask(recordId: "r1", douyinAccountId: "acc1", attachments: [videoAttachment], content: "任务1"),
            PublishTask(recordId: "r2", douyinAccountId: "acc2", attachments: [videoAttachment], content: "任务2"),
            PublishTask(recordId: "r3", douyinAccountId: "acc3", attachments: [videoAttachment], content: "任务3"),
            PublishTask(recordId: "r4", douyinAccountId: "acc4", attachments: [videoAttachment], content: "任务4")
        ]
        vm.successCount = 2
        vm.failedCount = 1

        // 已完成 3/4
        XCTAssertEqual(vm.progress, 0.75, accuracy: 0.001)
        XCTAssertEqual(vm.remainingCount, 1)
    }

    // MARK: - 账号登录状态（canStartExecution）

    @MainActor
    func testCanStartExecution_allLoggedIn_returnsTrue() {
        let vm = ExecutionViewModel()
        let videoAttachment = FeishuAttachment(
            fileToken: "token1",
            name: "video.mp4",
            type: "video/mp4",
            size: 10000,
            url: nil
        )
        vm.validTasks = [
            PublishTask(recordId: "r1", douyinAccountId: "acc1", attachments: [videoAttachment], content: "任务1")
        ]
        vm.requiredAccounts = ["acc1"]
        vm.loggedInAccounts = ["acc1"]
        vm.expiredAccounts = []

        XCTAssertTrue(vm.canStartExecution)
    }

    @MainActor
    func testCanStartExecution_someExpired_returnsFalse() {
        let vm = ExecutionViewModel()
        let videoAttachment = FeishuAttachment(
            fileToken: "token1",
            name: "video.mp4",
            type: "video/mp4",
            size: 10000,
            url: nil
        )
        vm.validTasks = [
            PublishTask(recordId: "r1", douyinAccountId: "acc1", attachments: [videoAttachment], content: "任务1")
        ]
        vm.requiredAccounts = ["acc1", "acc2"]
        vm.loggedInAccounts = ["acc1"]
        vm.expiredAccounts = ["acc2"]

        XCTAssertFalse(vm.canStartExecution)
    }

    // MARK: - 日志保存集成测试

    @MainActor
    func testSaveLog_onCompleted() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("exec_vm_log_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = LogStore(logsDirectory: tempDir)
        let vm = ExecutionViewModel(logStore: logStore)

        // 模拟执行完成后的日志数据
        var log = ExecutionLog(feishuConfigName: "测试配置", total: 3)
        log.addEntry(level: .info, message: "开始执行")
        log.successCount = 2
        log.failedCount = 1
        log.finishedAt = Date()
        vm.executionLog = log

        // 调用保存方法
        vm.saveExecutionLog()

        // 验证日志已持久化
        let saved = logStore.loadAll()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.feishuConfigName, "测试配置")
        XCTAssertEqual(saved.first?.successCount, 2)
        XCTAssertEqual(saved.first?.failedCount, 1)
    }

    @MainActor
    func testSaveLog_onStopped() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("exec_vm_log_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = LogStore(logsDirectory: tempDir)
        let vm = ExecutionViewModel(logStore: logStore)

        // 模拟中止场景
        var log = ExecutionLog(feishuConfigName: "中止配置", total: 5)
        log.addEntry(level: .warning, message: "用户中止")
        log.successCount = 1
        log.failedCount = 0
        log.finishedAt = Date()
        vm.executionLog = log

        vm.saveExecutionLog()

        let saved = logStore.loadAll()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.feishuConfigName, "中止配置")
    }

    @MainActor
    func testSaveLog_nilExecutionLog_doesNotCrash() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("exec_vm_log_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = LogStore(logsDirectory: tempDir)
        let vm = ExecutionViewModel(logStore: logStore)
        vm.executionLog = nil

        // 不应崩溃
        vm.saveExecutionLog()

        let saved = logStore.loadAll()
        XCTAssertTrue(saved.isEmpty)
    }
}
