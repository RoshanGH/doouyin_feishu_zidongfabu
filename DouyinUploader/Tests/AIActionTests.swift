import XCTest
@testable import DouyinUploader

final class AIActionTests: XCTestCase {

    // MARK: - AIAction 相等性

    func test_clickActionsEqual() {
        XCTAssertEqual(AIAction.click(x: 100, y: 200), AIAction.click(x: 100, y: 200))
        XCTAssertNotEqual(AIAction.click(x: 100, y: 200), AIAction.click(x: 100, y: 201))
    }

    func test_typeActionsEqual() {
        XCTAssertEqual(AIAction.type(text: "hello"), AIAction.type(text: "hello"))
        XCTAssertNotEqual(AIAction.type(text: "a"), AIAction.type(text: "b"))
    }

    func test_differentActionTypesNotEqual() {
        XCTAssertNotEqual(AIAction.click(x: 0, y: 0), AIAction.type(text: ""))
        XCTAssertNotEqual(AIAction.wait(seconds: 1), AIAction.completed(message: ""))
    }

    // MARK: - AIAnalysisResult

    func test_analysisResultCreation() {
        let result = AIAnalysisResult(
            status: .popup,
            action: .click(x: 850, y: 120),
            description: "页面有一个活动弹窗，右上角有关闭按钮"
        )
        XCTAssertEqual(result.status, .popup)
        XCTAssertEqual(result.action, .click(x: 850, y: 120))
        XCTAssertEqual(result.description, "页面有一个活动弹窗，右上角有关闭按钮")
    }

    func test_pageStatusValues() {
        XCTAssertEqual(AIAnalysisResult.PageStatus.normal.rawValue, "normal")
        XCTAssertEqual(AIAnalysisResult.PageStatus.captcha.rawValue, "captcha")
        XCTAssertEqual(AIAnalysisResult.PageStatus.loginExpired.rawValue, "loginExpired")
        XCTAssertEqual(AIAnalysisResult.PageStatus.publishSuccess.rawValue, "publishSuccess")
    }

    // MARK: - AIConfig

    func test_defaultConfig() {
        XCTAssertEqual(AIConfig.defaultBaseURL, "https://apicn.unifyllm.top/v1")
        XCTAssertEqual(AIConfig.defaultModel, "claude-sonnet-4-6")
    }

    func test_configCreation() {
        let config = AIConfig(
            baseURL: "https://custom.api.com/v1",
            apiKey: "sk-test123",
            model: "gpt-4o"
        )
        XCTAssertEqual(config.baseURL, "https://custom.api.com/v1")
        XCTAssertEqual(config.apiKey, "sk-test123")
        XCTAssertEqual(config.model, "gpt-4o")
    }
}
