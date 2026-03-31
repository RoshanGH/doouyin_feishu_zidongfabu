import Foundation

/// AI 决策层 — 截图 → AI 分析 → 返回操作指令
/// 负责：构建 prompt、调用 AIVisionService、解析响应、管理操作历史、重复检测
final class AIAgent {

    private let visionService: AIVisionService
    private let driver: CDPDriver

    /// 操作历史（最近 5 步，用于重复检测）
    private var actionHistory: [AIAction] = []
    private let maxHistorySize = 5

    /// 日志回调
    var onLog: ((LogLevel, String) -> Void)?

    init(config: AIConfig, driver: CDPDriver) {
        self.visionService = AIVisionService(config: config)
        self.driver = driver
    }

    // MARK: - 核心方法

    /// 截图并让 AI 分析当前页面状态
    func analyzePage(
        taskDescription: String,
        currentStep: String,
        content: String = "",
        tags: [String] = []
    ) async throws -> AIAnalysisResult {
        let screenshot = try await driver.screenshot()
        let prompt = AIPromptBuilder.buildPageAnalysis(
            taskDescription: taskDescription,
            currentStep: currentStep,
            content: content,
            tags: tags
        )
        log(.info, "AI 分析中...")
        let result = try await visionService.analyze(screenshot: screenshot, prompt: prompt)
        log(.info, "AI 判断: \(result.status.rawValue) — \(result.description)")
        recordAction(result.action)
        return result
    }

    /// 让 AI 定位页面上的指定元素
    func findElement(description: String) async throws -> AIAnalysisResult {
        let screenshot = try await driver.screenshot()
        let prompt = AIPromptBuilder.buildFindElement(elementDescription: description)
        log(.info, "AI 定位: \(description)")
        let result = try await visionService.analyze(screenshot: screenshot, prompt: prompt)
        log(.info, "AI 结果: \(result.description)")
        recordAction(result.action)
        return result
    }

    /// 截图验证上一步操作是否成功
    func verifyAction(expectedChange: String) async throws -> AIAnalysisResult {
        let screenshot = try await driver.screenshot()
        let prompt = AIPromptBuilder.buildVerifyAction(expectedChange: expectedChange)
        let result = try await visionService.analyze(screenshot: screenshot, prompt: prompt)
        return result
    }

    /// 安全的 AI 指导点击（含坐标校验 + 操作后验证 + 重试）
    func safeClick(
        elementDescription: String,
        verifyDescription: String,
        maxRetries: Int = 3
    ) async throws {
        for attempt in 1...maxRetries {
            if isStuck {
                throw AIAgentError.stuck
            }
            let result = try await findElement(description: elementDescription)
            guard case .click(let x, let y) = result.action else {
                if attempt == maxRetries {
                    throw AIAgentError.elementNotFound(elementDescription)
                }
                continue
            }

            // 坐标缩放：截图压缩到 640px 宽，AI 返回的是 640px 坐标系
            // CDP 点击需要实际视口坐标（1280px），所以 x2
            let scaledX = x * 2
            let scaledY = y * 2

            guard AIResponseParser.isValidCoordinate(x: scaledX, y: scaledY, viewportWidth: 1280, viewportHeight: 800) else {
                log(.warning, "AI 返回坐标不合理: (\(x), \(y)) → 缩放后 (\(scaledX), \(scaledY))，重试 \(attempt)/\(maxRetries)")
                continue
            }

            // 执行点击（使用缩放后的坐标）
            log(.info, "AI 点击: (\(x),\(y)) → 缩放 (\(scaledX),\(scaledY))")
            try await driver.click(x: scaledX, y: scaledY)
            try await Task.sleep(nanoseconds: 1_500_000_000)

            // 验证操作结果
            let verification = try await verifyAction(expectedChange: verifyDescription)
            if verification.status != .error {
                return // 操作成功
            }

            log(.warning, "AI 操作验证失败，重试 \(attempt)/\(maxRetries)")
        }
        throw AIAgentError.maxRetriesExceeded(elementDescription)
    }

    /// 检测页面是否有弹窗，如果有则自动处理
    /// 返回 true 表示有弹窗且已处理，false 表示无弹窗
    func checkAndHandlePopup(taskDescription: String) async throws -> Bool {
        let result = try await analyzePage(
            taskDescription: taskDescription,
            currentStep: "检查弹窗"
        )

        switch result.status {
        case .popup:
            // AI 找到了弹窗的关闭按钮
            if case .click(let x, let y) = result.action {
                log(.info, "AI 检测到弹窗，点击关闭: (\(x), \(y))")
                try await driver.click(x: x, y: y)
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return true
            }
            return false

        case .captcha:
            // 验证码需要用户手动处理
            if case .waitForUser(let message) = result.action {
                throw AIAgentError.captchaDetected(message)
            }
            throw AIAgentError.captchaDetected("页面出现验证码")

        case .loginExpired:
            throw AIAgentError.loginExpired

        case .normal, .uploadComplete, .publishSuccess:
            return false // 无弹窗

        case .error:
            return false
        }
    }

    // MARK: - 重复检测

    /// 检测是否连续执行了相同操作（可能卡住了）
    var isStuck: Bool {
        guard actionHistory.count >= 3 else { return false }
        let last3 = actionHistory.suffix(3)
        return last3.allSatisfy { $0 == last3.first }
    }

    /// 记录操作到历史
    private func recordAction(_ action: AIAction) {
        actionHistory.append(action)
        if actionHistory.count > maxHistorySize {
            actionHistory.removeFirst()
        }
    }

    /// 清空操作历史
    func resetHistory() {
        actionHistory.removeAll()
    }

    // MARK: - 测试 API 连接

    func testConnection() async throws -> String {
        try await visionService.testConnection()
    }

    private func log(_ level: LogLevel, _ message: String) {
        onLog?(level, message)
    }
}

// MARK: - 错误类型

enum AIAgentError: LocalizedError {
    case elementNotFound(String)
    case maxRetriesExceeded(String)
    case captchaDetected(String)
    case loginExpired
    case stuck

    var errorDescription: String? {
        switch self {
        case .elementNotFound(let desc): return "AI 未找到元素: \(desc)"
        case .maxRetriesExceeded(let desc): return "AI 操作重试 3 次仍失败: \(desc)"
        case .captchaDetected(let msg): return "验证码: \(msg)"
        case .loginExpired: return "AI 检测到登录过期"
        case .stuck: return "AI 操作陷入循环"
        }
    }
}
