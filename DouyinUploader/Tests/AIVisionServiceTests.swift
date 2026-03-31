import XCTest
@testable import DouyinUploader

final class AIVisionServiceTests: XCTestCase {

    // MARK: - JSON 响应解析

    func test_parseValidClickAction() throws {
        let json = """
        {
            "status": "popup",
            "description": "页面有活动弹窗",
            "action": {
                "type": "click",
                "x": 850,
                "y": 120
            }
        }
        """
        let result = try AIResponseParser.parse(json)
        XCTAssertEqual(result.status, .popup)
        XCTAssertEqual(result.action, .click(x: 850, y: 120))
        XCTAssertEqual(result.description, "页面有活动弹窗")
    }

    func test_parseTypeAction() throws {
        let json = """
        {
            "status": "normal",
            "description": "需要输入文案",
            "action": {
                "type": "type",
                "text": "测试文案"
            }
        }
        """
        let result = try AIResponseParser.parse(json)
        XCTAssertEqual(result.action, .type(text: "测试文案"))
    }

    func test_parseCompletedAction() throws {
        let json = """
        {
            "status": "publishSuccess",
            "description": "发布成功",
            "action": {
                "type": "completed",
                "message": "页面已跳转到内容管理"
            }
        }
        """
        let result = try AIResponseParser.parse(json)
        XCTAssertEqual(result.status, .publishSuccess)
        XCTAssertEqual(result.action, .completed(message: "页面已跳转到内容管理"))
    }

    func test_parseWaitForUserAction() throws {
        let json = """
        {
            "status": "captcha",
            "description": "页面出现滑块验证码",
            "action": {
                "type": "waitForUser",
                "message": "请手动完成验证码"
            }
        }
        """
        let result = try AIResponseParser.parse(json)
        XCTAssertEqual(result.status, .captcha)
        XCTAssertEqual(result.action, .waitForUser(message: "请手动完成验证码"))
    }

    func test_parseErrorAction() throws {
        let json = """
        {
            "status": "loginExpired",
            "description": "登录已过期",
            "action": {
                "type": "error",
                "message": "需要重新登录"
            }
        }
        """
        let result = try AIResponseParser.parse(json)
        XCTAssertEqual(result.status, .loginExpired)
        XCTAssertEqual(result.action, .error(message: "需要重新登录"))
    }

    func test_parsePressKeyAction() throws {
        let json = """
        {
            "status": "normal",
            "description": "需要按回车",
            "action": {
                "type": "pressKey",
                "key": "Enter"
            }
        }
        """
        let result = try AIResponseParser.parse(json)
        XCTAssertEqual(result.action, .pressKey(key: "Enter"))
    }

    func test_parseWaitAction() throws {
        let json = """
        {
            "status": "normal",
            "description": "等待上传",
            "action": {
                "type": "wait",
                "seconds": 5
            }
        }
        """
        let result = try AIResponseParser.parse(json)
        XCTAssertEqual(result.action, .wait(seconds: 5))
    }

    func test_parseInvalidJSON_throws() {
        XCTAssertThrowsError(try AIResponseParser.parse("not json")) { error in
            XCTAssertTrue(error is AIResponseParser.ParseError)
        }
    }

    func test_parseMissingAction_throws() {
        let json = """
        {
            "status": "normal",
            "description": "缺少action"
        }
        """
        XCTAssertThrowsError(try AIResponseParser.parse(json))
    }

    func test_parseUnknownActionType_throws() {
        let json = """
        {
            "status": "normal",
            "description": "未知操作",
            "action": {
                "type": "fly_to_moon"
            }
        }
        """
        XCTAssertThrowsError(try AIResponseParser.parse(json))
    }

    // MARK: - 坐标合理性校验

    func test_coordinateValidation_valid() {
        XCTAssertTrue(AIResponseParser.isValidCoordinate(x: 640, y: 400, viewportWidth: 1280, viewportHeight: 800))
    }

    func test_coordinateValidation_negative() {
        XCTAssertFalse(AIResponseParser.isValidCoordinate(x: -1, y: 400, viewportWidth: 1280, viewportHeight: 800))
    }

    func test_coordinateValidation_outOfBounds() {
        XCTAssertFalse(AIResponseParser.isValidCoordinate(x: 1300, y: 400, viewportWidth: 1280, viewportHeight: 800))
    }

    func test_coordinateValidation_zero() {
        XCTAssertTrue(AIResponseParser.isValidCoordinate(x: 0, y: 0, viewportWidth: 1280, viewportHeight: 800))
    }

    // MARK: - Prompt 构建

    func test_buildPrompt_containsTaskInfo() {
        let prompt = AIPromptBuilder.buildPageAnalysis(
            taskDescription: "发布视频",
            currentStep: "设置封面",
            content: "测试文案",
            tags: ["测试", "标签"]
        )
        XCTAssertTrue(prompt.contains("发布视频"))
        XCTAssertTrue(prompt.contains("设置封面"))
        XCTAssertTrue(prompt.contains("测试文案"))
    }

    func test_buildPrompt_containsJSONInstruction() {
        let prompt = AIPromptBuilder.buildPageAnalysis(
            taskDescription: "发布视频",
            currentStep: "上传",
            content: "",
            tags: []
        )
        XCTAssertTrue(prompt.contains("JSON"))
    }
}
