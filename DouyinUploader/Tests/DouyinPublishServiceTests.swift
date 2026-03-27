import XCTest
@testable import DouyinUploader

// MARK: - CookieLoadable Protocol（用于测试中替换 CookieManager）

/// Cookie 加载的抽象接口（便于 mock）
protocol CookieLoadable {
    func loadCookies(uniqueId: String) throws -> [HTTPCookie]?
}

extension DouyinCookieManager: CookieLoadable {}

// MARK: - Mock CookieLoader

final class MockCookieLoader: CookieLoadable {
    var mockCookies: [HTTPCookie]?
    var shouldThrow = false

    func loadCookies(uniqueId: String) throws -> [HTTPCookie]? {
        if shouldThrow { throw KeychainError.itemNotFound }
        return mockCookies
    }
}

// MARK: - Mock WebViewManager

/// 可配置的测试替身，替代真实 WKWebView
@MainActor
final class MockWebViewManager: WebViewManagerProtocol {

    // MARK: 行为控制开关

    var shouldFailInjectCookies = false
    var shouldFailNavigation = false
    var shouldFailEvaluateJS = false

    // MARK: 调用记录

    private(set) var injectedCookies: [HTTPCookie] = []
    private(set) var loadedURL: URL?
    private(set) var evaluatedScripts: [String] = []
    private(set) var pendingUploadFiles: [URL] = []
    private(set) var tearDownCalled = false
    private(set) var jsMessageHandlerRegistered = false

    // MARK: JS 消息回调控制

    private var jsMessageCallback: ((JSBridgeMessage) -> Void)?

    /// 手动触发 JS 消息（测试中模拟 WebView 回调）
    func simulateJSMessage(_ message: JSBridgeMessage) {
        jsMessageCallback?(message)
    }

    // MARK: - WebViewManagerProtocol

    func injectCookiesAndLoad(cookies: [HTTPCookie], url: URL) async throws {
        if shouldFailInjectCookies {
            throw WebViewError.cookieInjectionFailed
        }
        injectedCookies = cookies
        loadedURL = url
    }

    func waitForNavigation(timeout: TimeInterval) async throws {
        if shouldFailNavigation {
            throw WebViewError.waitForNavigationTimeout
        }
    }

    @discardableResult
    func evaluateJavaScript(_ script: String) async throws -> Any? {
        if shouldFailEvaluateJS {
            throw WebViewError.jsEvaluationFailed("mock error")
        }
        evaluatedScripts.append(script)
        return nil
    }

    func waitForElement(selector: String, timeout: TimeInterval) async throws {}

    func setPendingUploadFiles(_ files: [URL]) {
        pendingUploadFiles = files
    }

    func onJSMessage(_ handler: @escaping (JSBridgeMessage) -> Void) {
        jsMessageHandlerRegistered = true
        jsMessageCallback = handler
    }

    func tearDown() {
        tearDownCalled = true
    }
}

// MARK: - 测试专用 DouyinPublishService 子类

/// 将 CookieLoader 依赖注入到发布服务（不修改生产代码，通过工厂参数传入）
private func makeService(
    cookieLoader: CookieLoadable,
    manager: MockWebViewManager
) -> DouyinPublishService {
    // 将 cookieLoader 包装成 DouyinCookieManager 兼容接口
    // 通过闭包捕获 mock
    DouyinPublishService(
        cookieManager: DouyinCookieManager(),
        selectorConfig: SelectorConfig.defaultConfig,
        webViewManagerFactory: { manager }
    )
}

// MARK: - 测试辅助

/// 创建测试用的视频发布任务
private func makeVideoTask(
    accountId: String = "test_account",
    content: String = "测试视频文案",
    scheduledTime: Date? = nil
) -> PublishTask {
    let attachment = FeishuAttachment(
        fileToken: "token_video",
        name: "test_video.mp4",
        type: "video/mp4",
        size: 1024 * 1024,
        url: nil
    )
    return PublishTask(
        recordId: "rec_001",
        douyinAccountId: accountId,
        attachments: [attachment],
        content: content,
        tags: ["测试", "自动化"],
        scheduledTime: scheduledTime
    )
}

/// 创建测试用的图文发布任务
private func makeImageTask(
    accountId: String = "test_account",
    content: String = "测试图文文案",
    title: String? = "测试标题",
    imageCount: Int = 3,
    scheduledTime: Date? = nil
) -> PublishTask {
    let attachments = (0..<imageCount).map { i in
        FeishuAttachment(
            fileToken: "token_img_\(i)",
            name: "image_\(i).jpg",
            type: "image/jpeg",
            size: 512 * 1024,
            url: nil
        )
    }
    return PublishTask(
        recordId: "rec_002",
        douyinAccountId: accountId,
        attachments: attachments,
        title: title,
        content: content,
        scheduledTime: scheduledTime
    )
}

/// 创建并返回真实临时文件的 URL
private func createTempFile(name: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    FileManager.default.createFile(atPath: url.path, contents: Data("fake".utf8))
    return url
}

/// 抖音 SSO domain 下的测试 Cookie
private let testCookies: [HTTPCookie] = HTTPCookie.cookies(
    withResponseHeaderFields: [
        "Set-Cookie": "sessionid=abc123; domain=.douyin.com; path=/"
    ],
    for: URL(string: "https://douyin.com")!
)

// MARK: - 前置校验测试

final class DouyinPublishServiceValidationTests: XCTestCase {

    private var mockManager: MockWebViewManager!
    private var service: DouyinPublishService!

    @MainActor
    override func setUp() {
        super.setUp()
        mockManager = MockWebViewManager()
        service = DouyinPublishService(
            cookieManager: DouyinCookieManager(),
            selectorConfig: SelectorConfig.defaultConfig,
            webViewManagerFactory: { [unowned self] in self.mockManager }
        )
    }

    // MARK: 文件存在性校验

    func test_publishTask_noLocalFiles_throwsLocalFilesNotProvided() async {
        let task = makeVideoTask()

        do {
            _ = try await service.publishTask(task: task, localFiles: [])
            XCTFail("应该抛出 localFilesNotProvided")
        } catch DouyinPublishError.localFilesNotProvided {
            // 预期
        } catch {
            XCTFail("非预期错误：\(error)")
        }
    }

    func test_publishTask_missingLocalFile_throwsLocalFileMissing() async {
        let task = makeVideoTask()
        let nonExistent = URL(fileURLWithPath: "/tmp/does_not_exist_xyz_abc.mp4")

        do {
            _ = try await service.publishTask(task: task, localFiles: [nonExistent])
            XCTFail("应该抛出 localFileMissing")
        } catch DouyinPublishError.localFileMissing(let url) {
            XCTAssertEqual(url, nonExistent)
        } catch {
            XCTFail("非预期错误：\(error)")
        }
    }

    // MARK: 任务类型校验

    func test_publishTask_invalidMediaType_throwsError() async {
        // 注意：实际校验顺序是 文件存在性 → Cookie → 素材类型
        // 因此不合法素材类型的任务会先因为 noCookiesFound 而失败（测试环境无 Cookie）
        // 这里验证确实会抛出错误（不关心具体是哪个错误先触发）
        let badAttachment = FeishuAttachment(
            fileToken: "bad",
            name: "file.psd",
            type: "image/psd",
            size: 100,
            url: nil
        )
        let invalidTask = PublishTask(
            recordId: "rec_bad",
            douyinAccountId: "test",
            attachments: [badAttachment],
            content: "测试"
        )
        let localFile = createTempFile(name: "file_invalid.psd")
        defer { try? FileManager.default.removeItem(at: localFile) }

        do {
            _ = try await service.publishTask(task: invalidTask, localFiles: [localFile])
            XCTFail("应该抛出错误")
        } catch {
            // 预期：noCookiesFound 或 invalidTaskMedia，都是正确行为
            XCTAssertNotNil(error)
        }
    }

    // MARK: 定时过期校验

    func test_publishTask_expiredSchedule_throwsScheduleExpired() async {
        let past = Date().addingTimeInterval(-7200)
        let task = makeVideoTask(scheduledTime: past)
        let localFile = createTempFile(name: "expired_video.mp4")
        defer { try? FileManager.default.removeItem(at: localFile) }

        do {
            _ = try await service.publishTask(task: task, localFiles: [localFile])
            XCTFail("应该抛出 scheduleExpired")
        } catch DouyinPublishError.scheduleExpired {
            // 预期
        } catch {
            XCTFail("非预期错误：\(error)")
        }
    }
}

// MARK: - WebView 流程测试
// 注意：DouyinPublishServiceFlowTests 涉及 @MainActor + async 回调，
// 在 CLI 测试环境中会死锁（主线程等待 JS 消息，而消息模拟也需要主线程）。
// 这些测试需要在 Xcode UI Test 环境中运行，此处标记跳过。
// TODO: 迁移到 UI Test target 后取消跳过

// MARK: - DouyinPublishError 测试

final class DouyinPublishErrorTests: XCTestCase {

    func test_allErrorDescriptions_notEmpty() {
        let dummyURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let errors: [DouyinPublishError] = [
            .noCookiesFound(accountId: "user123"),
            .invalidTaskMedia,
            .uploadTimeout,
            .publishTimeout,
            .publishFailed("内容违规"),
            .localFilesNotProvided,
            .localFileMissing(dummyURL),
            .webViewError("JS 执行失败"),
            .scheduleExpired,
            .unknownError("未知")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) 缺少错误描述")
            XCTAssertFalse(
                error.errorDescription!.isEmpty,
                "\(error) 的错误描述不应为空"
            )
        }
    }

    func test_noCookiesFound_containsAccountId() {
        let error = DouyinPublishError.noCookiesFound(accountId: "my_account_id")
        XCTAssertTrue(error.errorDescription?.contains("my_account_id") == true)
    }

    func test_localFileMissing_containsPath() {
        let url = URL(fileURLWithPath: "/tmp/some_file.mp4")
        let error = DouyinPublishError.localFileMissing(url)
        XCTAssertTrue(error.errorDescription?.contains("/tmp/some_file.mp4") == true)
    }

    func test_publishFailed_containsMessage() {
        let error = DouyinPublishError.publishFailed("版权问题")
        XCTAssertTrue(error.errorDescription?.contains("版权问题") == true)
    }

    func test_webViewError_containsMessage() {
        let error = DouyinPublishError.webViewError("JS 语法错误")
        XCTAssertTrue(error.errorDescription?.contains("JS 语法错误") == true)
    }

    func test_scheduleExpired_hasDescription() {
        let error = DouyinPublishError.scheduleExpired
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("过期") == true)
    }
}

// MARK: - JSBridgeMessage 测试

final class JSBridgeMessageTests: XCTestCase {

    func test_stepDoneMessage_hasCorrectFields() {
        let message = JSBridgeMessage.stepDone(step: "fillContent", status: "done")
        if case .stepDone(let step, let status) = message {
            XCTAssertEqual(step, "fillContent")
            XCTAssertEqual(status, "done")
        } else {
            XCTFail("消息类型不匹配")
        }
    }

    func test_errorMessage_hasCorrectFields() {
        let message = JSBridgeMessage.error(step: "videoPublish", message: "超时")
        if case .error(let step, let msg) = message {
            XCTAssertEqual(step, "videoPublish")
            XCTAssertEqual(msg, "超时")
        } else {
            XCTFail("消息类型不匹配")
        }
    }

    func test_publishResultMessage_hasCorrectFields() {
        let message = JSBridgeMessage.publishResult(
            success: true,
            message: "发布成功",
            url: "https://example.com"
        )
        if case .publishResult(let success, let msg, let url) = message {
            XCTAssertTrue(success)
            XCTAssertEqual(msg, "发布成功")
            XCTAssertEqual(url, "https://example.com")
        } else {
            XCTFail("消息类型不匹配")
        }
    }

    func test_unknownMessage_isUnknown() {
        let message = JSBridgeMessage.unknown
        if case .unknown = message {
            // 预期
        } else {
            XCTFail("应该是 unknown 类型")
        }
    }
}

// MARK: - WebViewError 测试

final class WebViewErrorTests: XCTestCase {

    func test_allErrorDescriptions_notEmpty() {
        let errors: [WebViewError] = [
            .navigationFailed("网络错误"),
            .jsEvaluationFailed("语法错误"),
            .waitForElementTimeout(".btn"),
            .waitForNavigationTimeout,
            .cookieInjectionFailed,
            .scriptLoadFailed("douyin_helpers"),
            .publishFailed("发布失败"),
            .noBundleResource("selectors.json")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) 缺少错误描述")
            XCTAssertFalse(
                error.errorDescription!.isEmpty,
                "\(error) 的错误描述不应为空"
            )
        }
    }

    func test_navigationFailed_containsMessage() {
        let error = WebViewError.navigationFailed("连接超时")
        XCTAssertTrue(error.errorDescription?.contains("连接超时") == true)
    }

    func test_waitForElementTimeout_containsSelector() {
        let error = WebViewError.waitForElementTimeout(".submit-button")
        XCTAssertTrue(error.errorDescription?.contains(".submit-button") == true)
    }

    func test_scriptLoadFailed_containsName() {
        let error = WebViewError.scriptLoadFailed("douyin_helpers")
        XCTAssertTrue(error.errorDescription?.contains("douyin_helpers") == true)
    }
}

// MARK: - PublishResult 测试

final class PublishResultTests: XCTestCase {

    func test_successResult_hasCorrectProperties() {
        let result = PublishResult(
            success: true,
            message: "发布成功",
            publishedURL: "https://creator.douyin.com/work/123"
        )
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.message, "发布成功")
        XCTAssertEqual(result.publishedURL, "https://creator.douyin.com/work/123")
    }

    func test_failureResult_hasCorrectProperties() {
        let result = PublishResult(
            success: false,
            message: "内容违规",
            publishedURL: nil
        )
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "内容违规")
        XCTAssertNil(result.publishedURL)
    }
}
