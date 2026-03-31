import XCTest
@testable import DouyinUploader

// MARK: - 测试用 Mock CDPDriver

final class MockCDPDriver: CDPDriver {
    func screenshot() async throws -> Data { Data() }
    func click(x: Int, y: Int) async throws {}
    func type(text: String) async throws {}
    func pressKey(_ key: String) async throws {}
    func uploadFiles(selector: String, paths: [String]) async throws {}
    func scroll(deltaX: Int, deltaY: Int) async throws {}
    func navigate(to url: String) async throws {}
    func getCurrentURL() async throws -> String { "" }
    func evaluate(_ js: String) async throws -> Any? { nil }
}

// MARK: - AIAgentStuckDetector — isStuck 算法的独立可测试实现
//
// AIAgent 内部的 isStuck 逻辑：
//   - 历史 < 3 条 → false
//   - 最近 3 条全部相同 → true
//   - 否则 → false
//
// 该结构体与 AIAgent 的算法完全一致，用于单元测试。

struct AIAgentStuckDetector {
    private var history: [AIAction] = []
    private let maxSize: Int
    private let threshold: Int

    init(maxSize: Int = 5, threshold: Int = 3) {
        self.maxSize = maxSize
        self.threshold = threshold
    }

    mutating func record(_ action: AIAction) {
        history.append(action)
        if history.count > maxSize {
            history.removeFirst()
        }
    }

    var isStuck: Bool {
        guard history.count >= threshold else { return false }
        let lastN = history.suffix(threshold)
        return lastN.allSatisfy { $0 == lastN.first }
    }

    mutating func reset() {
        history.removeAll()
    }
}

// MARK: - 测试套件

final class AIAgentTests: XCTestCase {

    // MARK: - isStuck 检测：连续 3 次相同操作 = stuck

    func test_isStuck_whenThreeSameActions_returnsTrue() {
        var detector = AIAgentStuckDetector()

        detector.record(.click(x: 100, y: 200))
        detector.record(.click(x: 100, y: 200))
        detector.record(.click(x: 100, y: 200))

        XCTAssertTrue(detector.isStuck, "连续 3 次相同操作应判定为 stuck")
    }

    func test_isStuck_whenFiveSameActions_returnsTrue() {
        var detector = AIAgentStuckDetector()

        for _ in 1...5 {
            detector.record(.wait(seconds: 2))
        }

        XCTAssertTrue(detector.isStuck, "连续 5 次相同操作应判定为 stuck")
    }

    // MARK: - isStuck 检测：不同操作 = not stuck

    func test_isStuck_whenDifferentActions_returnsFalse() {
        var detector = AIAgentStuckDetector()

        detector.record(.click(x: 100, y: 200))
        detector.record(.type(text: "hello"))
        detector.record(.pressKey(key: "Enter"))

        XCTAssertFalse(detector.isStuck, "不同操作不应判定为 stuck")
    }

    func test_isStuck_whenTwoSameThenOneDifferent_returnsFalse() {
        var detector = AIAgentStuckDetector()

        detector.record(.click(x: 50, y: 50))
        detector.record(.click(x: 50, y: 50))
        detector.record(.wait(seconds: 1))

        XCTAssertFalse(detector.isStuck, "最后一步不同，不应判定为 stuck")
    }

    func test_isStuck_whenLessThanThreeActions_returnsFalse() {
        var detector = AIAgentStuckDetector()

        detector.record(.click(x: 100, y: 200))
        detector.record(.click(x: 100, y: 200))

        XCTAssertFalse(detector.isStuck, "少于 3 条记录不应判定为 stuck")
    }

    func test_isStuck_whenEmpty_returnsFalse() {
        let detector = AIAgentStuckDetector()
        XCTAssertFalse(detector.isStuck, "空历史不应判定为 stuck")
    }

    // MARK: - resetHistory 清空后 isStuck 为 false

    func test_isStuck_afterReset_returnsFalse() {
        var detector = AIAgentStuckDetector()

        detector.record(.click(x: 100, y: 200))
        detector.record(.click(x: 100, y: 200))
        detector.record(.click(x: 100, y: 200))
        XCTAssertTrue(detector.isStuck, "重置前应为 stuck")

        detector.reset()
        XCTAssertFalse(detector.isStuck, "重置后不应为 stuck")
    }

    func test_isStuck_afterResetAndNewDifferentActions_returnsFalse() {
        var detector = AIAgentStuckDetector()

        for _ in 1...3 {
            detector.record(.wait(seconds: 5))
        }
        detector.reset()
        detector.record(.click(x: 10, y: 20))
        detector.record(.type(text: "abc"))

        XCTAssertFalse(detector.isStuck, "重置后加入新操作不应为 stuck")
    }

    // MARK: - maxSize 滑动窗口正确性

    func test_maxSize_oldActionsEvicted() {
        var detector = AIAgentStuckDetector(maxSize: 5, threshold: 3)

        for _ in 1...5 {
            detector.record(.click(x: 1, y: 1))
        }
        // 追加 3 个 wait，最老的 3 条 click 被挤出窗口
        detector.record(.wait(seconds: 1))
        detector.record(.wait(seconds: 1))
        detector.record(.wait(seconds: 1))

        // 最近 3 条是 wait(1)，应判定为 stuck
        XCTAssertTrue(detector.isStuck, "滑动窗口内最近 3 条相同应为 stuck")
    }

    // MARK: - AIAgentError 错误描述

    func test_elementNotFoundError_hasCorrectDescription() {
        let error = AIAgentError.elementNotFound("发布按钮")
        XCTAssertEqual(error.errorDescription, "AI 未找到元素: 发布按钮")
    }

    func test_maxRetriesExceededError_hasCorrectDescription() {
        let error = AIAgentError.maxRetriesExceeded("标题输入框")
        XCTAssertEqual(error.errorDescription, "AI 操作重试 3 次仍失败: 标题输入框")
    }

    func test_captchaDetectedError_hasCorrectDescription() {
        let error = AIAgentError.captchaDetected("请完成滑块验证")
        XCTAssertEqual(error.errorDescription, "验证码: 请完成滑块验证")
    }

    func test_loginExpiredError_hasCorrectDescription() {
        let error = AIAgentError.loginExpired
        XCTAssertEqual(error.errorDescription, "AI 检测到登录过期")
    }

    func test_stuckError_hasCorrectDescription() {
        let error = AIAgentError.stuck
        XCTAssertEqual(error.errorDescription, "AI 操作陷入循环")
    }

    // MARK: - AIAgent 初始化与 resetHistory

    func test_agentInit_withValidConfig_doesNotCrash() {
        let config = AIConfig(
            baseURL: "https://api.example.com/v1",
            apiKey: "sk-test",
            model: "claude-sonnet-4-6"
        )
        let driver = MockCDPDriver()
        let agent = AIAgent(config: config, driver: driver)
        XCTAssertNotNil(agent)
    }

    func test_agentResetHistory_calledRepeatedly_doesNotCrash() {
        let config = AIConfig(
            baseURL: "https://api.example.com/v1",
            apiKey: "sk-test",
            model: "test-model"
        )
        let driver = MockCDPDriver()
        let agent = AIAgent(config: config, driver: driver)

        agent.resetHistory()
        agent.resetHistory()
        // 不崩溃即通过
    }
}
