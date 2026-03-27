import Foundation
import WebKit
import AppKit
import IOKit.pwr_mgt

// MARK: - WebViewManager 错误类型

/// WebViewManager 操作相关错误
enum WebViewError: LocalizedError {
    case navigationFailed(String)
    case jsEvaluationFailed(String)
    case waitForElementTimeout(String)
    case waitForNavigationTimeout
    case cookieInjectionFailed
    case scriptLoadFailed(String)
    case publishFailed(String)
    case noBundleResource(String)

    var errorDescription: String? {
        switch self {
        case .navigationFailed(let msg):
            return "页面导航失败：\(msg)"
        case .jsEvaluationFailed(let msg):
            return "JavaScript 执行失败：\(msg)"
        case .waitForElementTimeout(let selector):
            return "等待元素超时：\(selector)"
        case .waitForNavigationTimeout:
            return "等待页面导航超时"
        case .cookieInjectionFailed:
            return "Cookie 注入失败"
        case .scriptLoadFailed(let name):
            return "加载 JS 脚本失败：\(name)"
        case .publishFailed(let msg):
            return "发布失败：\(msg)"
        case .noBundleResource(let name):
            return "Bundle 中未找到资源：\(name)"
        }
    }
}

// MARK: - JS Bridge 消息

/// 来自 WebView 的 JS 消息类型
enum JSBridgeMessage {
    case stepDone(step: String, status: String)
    case error(step: String, message: String)
    case publishResult(success: Bool, message: String, url: String)
    case unknown
}

// MARK: - WebViewManagerProtocol

/// WebViewManager 的抽象协议（便于单元测试中注入 mock）
/// 所有方法均在主线程执行
@MainActor
protocol WebViewManagerProtocol: AnyObject {
    /// 注入 Cookie 并加载指定 URL
    func injectCookiesAndLoad(
        cookies: [HTTPCookie],
        url: URL
    ) async throws

    /// 等待页面导航完成
    func waitForNavigation(timeout: TimeInterval) async throws

    /// 执行 JavaScript 并返回结果
    @discardableResult
    func evaluateJavaScript(_ script: String) async throws -> Any?

    /// 等待指定 CSS 选择器的元素出现
    func waitForElement(selector: String, timeout: TimeInterval) async throws

    /// 设置待上传的文件列表（供 WKUIDelegate 拦截文件选择框）
    func setPendingUploadFiles(_ files: [URL])

    /// 注册 JS 消息监听回调
    func onJSMessage(_ handler: @escaping (JSBridgeMessage) -> Void)

    /// 释放资源
    func tearDown()
}

// MARK: - WebViewManager

/// WKWebView 自动化操作封装
/// 每个账号发布任务创建一个独立实例，用完后调用 tearDown() 销毁
/// 必须在主线程（@MainActor）上创建和操作
@MainActor
final class WebViewManager: NSObject, WebViewManagerProtocol {

    // MARK: - 属性

    /// 离屏渲染用的 NSWindow（坐标设为屏幕外）
    private var offscreenWindow: NSWindow?

    /// 核心 WebView
    private(set) var webView: WKWebView?

    /// 待上传文件列表（WKUIDelegate 文件选择框拦截时返回）
    private var pendingUploadFiles: [URL] = []

    /// JS 消息回调
    private var jsMessageHandler: ((JSBridgeMessage) -> Void)?

    /// 导航完成的续体（用于 waitForNavigation）
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    /// 元素等待的续体（用于 waitForElement）
    private var elementContinuation: CheckedContinuation<Void, Error>?
    private var waitingForSelector: String?

    /// App Nap 防护令牌
    private var activityToken: NSObjectProtocol?

    /// IOKit 睡眠防护断言 ID
    private var sleepAssertionID: IOPMAssertionID = 0
    private var sleepAssertionActive = false

    // MARK: - 初始化

    override init() {
        super.init()
    }

    // MARK: - 设置 WebView

    /// 创建并配置 WKWebView（必须在主线程调用）
    func setup() throws {
        let config = makeWebViewConfiguration()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self

        // 读取调试模式设置
        let isDebug = SettingsManager().load().debugMode

        let window: NSWindow
        if isDebug {
            // 调试模式：窗口可见，方便观察 WebView 行为
            window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1280, height: 800),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "🔧 抖音发布调试窗口"
            window.contentView = wv
            window.makeKeyAndOrderFront(nil)
        } else {
            // 正常模式：离屏窗口
            window = NSWindow(
                contentRect: NSRect(x: -10000, y: -10000, width: 1280, height: 800),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = wv
            window.orderBack(nil)
        }

        self.webView = wv
        self.offscreenWindow = window

        // 防止 App Nap（系统可能在后台节能时暂停 WebView）
        enableActivityPrevention()
        enableSleepPrevention()
    }

    // MARK: - WebViewManagerProtocol

    func injectCookiesAndLoad(cookies: [HTTPCookie], url: URL) async throws {
        guard let wv = webView else {
            try setup()
            return try await injectCookiesAndLoad(cookies: cookies, url: url)
        }

        let store = wv.configuration.websiteDataStore.httpCookieStore
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()
            var injectionFailed = false

            for cookie in cookies {
                group.enter()
                store.setCookie(cookie) {
                    if cookie.name.isEmpty { injectionFailed = true }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if injectionFailed {
                    continuation.resume(throwing: WebViewError.cookieInjectionFailed)
                } else {
                    continuation.resume()
                }
            }
        }

        // 加载页面
        wv.load(URLRequest(url: url))
    }

    func waitForNavigation(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.navigationContinuation = continuation
            // 超时保护
            Task { @MainActor in
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if self.navigationContinuation != nil {
                    let cont = self.navigationContinuation
                    self.navigationContinuation = nil
                    cont?.resume(throwing: WebViewError.waitForNavigationTimeout)
                }
            }
        }
    }

    @discardableResult
    func evaluateJavaScript(_ script: String) async throws -> Any? {
        guard let wv = webView else {
            throw WebViewError.jsEvaluationFailed("WebView 未初始化")
        }

        return try await withCheckedThrowingContinuation { continuation in
            wv.evaluateJavaScript(script) { result, error in
                if let error = error {
                    continuation.resume(
                        throwing: WebViewError.jsEvaluationFailed(error.localizedDescription)
                    )
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    func waitForElement(selector: String, timeout: TimeInterval) async throws {
        // 通过 JS 的 waitForElement + messageHandler 回调实现
        let timeoutMs = Int(timeout * 1000)
        let escapedSelector = selector.replacingOccurrences(of: "'", with: "\\'")

        let script = """
        waitForElement('\(escapedSelector)', \(timeoutMs))
            .then(function() {
                window.notifySwift('stepDone', { step: 'waitElement', status: 'found', selector: '\(escapedSelector)' });
            })
            .catch(function(err) {
                window.notifySwift('error', { step: 'waitElement', message: err.message, selector: '\(escapedSelector)' });
            });
        """

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.elementContinuation = continuation
            self.waitingForSelector = selector

            // 超时保护
            Task { @MainActor in
                try await Task.sleep(nanoseconds: UInt64((timeout + 2) * 1_000_000_000))
                if let cont = self.elementContinuation,
                   self.waitingForSelector == selector {
                    self.elementContinuation = nil
                    self.waitingForSelector = nil
                    cont.resume(throwing: WebViewError.waitForElementTimeout(selector))
                }
            }

            Task { @MainActor in
                do {
                    try await self.evaluateJavaScript(script)
                } catch {
                    if self.elementContinuation != nil {
                        let cont = self.elementContinuation
                        self.elementContinuation = nil
                        self.waitingForSelector = nil
                        cont?.resume(throwing: error)
                    }
                }
            }
        }
    }

    func setPendingUploadFiles(_ files: [URL]) {
        pendingUploadFiles = files
    }

    func onJSMessage(_ handler: @escaping (JSBridgeMessage) -> Void) {
        jsMessageHandler = handler
    }

    func tearDown() {
        disableActivityPrevention()
        disableSleepPrevention()

        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil

        offscreenWindow?.close()
        offscreenWindow = nil

        jsMessageHandler = nil
        navigationContinuation = nil
        elementContinuation = nil
        pendingUploadFiles = []
    }

    // MARK: - 私有：WKWebViewConfiguration 构建

    private func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()

        // 使用非持久化 store 实现账号隔离
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        // 自定义 User-Agent（Chrome UA，避免被识别为自动化工具）
        config.applicationNameForUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/120.0.0.0 Safari/537.36"

        let contentController = WKUserContentController()

        // 注入通用工具库（atDocumentEnd，作用于所有帧）
        if let helpersScript = loadBundleJS(named: "douyin_helpers") {
            let userScript = WKUserScript(
                source: helpersScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            contentController.addUserScript(userScript)
        }

        // 注册 JS → Swift 消息通道
        contentController.add(
            WeakMessageHandler(delegate: self),
            name: "stepDone"
        )
        contentController.add(
            WeakMessageHandler(delegate: self),
            name: "error"
        )
        contentController.add(
            WeakMessageHandler(delegate: self),
            name: "publishResult"
        )

        config.userContentController = contentController

        // 允许弹出子窗口（部分抖音页面会用 window.open）
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        return config
    }

    // MARK: - 私有：Bundle JS 加载

    private func loadBundleJS(named name: String) -> String? {
        // 尝试 Bundle.module（Swift Package 资源）
        if let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "JS") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        // 备用路径
        if let url = Bundle.module.url(forResource: name, withExtension: "js") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        // 从 main bundle 查找
        if let url = Bundle.main.url(forResource: name, withExtension: "js") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }

    // MARK: - 私有：App Nap 防护

    private func enableActivityPrevention() {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "DouyinUploader 自动化发布中"
        )
    }

    private func disableActivityPrevention() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    // MARK: - 私有：IOKit 睡眠防护

    private func enableSleepPrevention() {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "DouyinUploader publishing" as CFString,
            &sleepAssertionID
        )
        sleepAssertionActive = (result == kIOReturnSuccess)
    }

    private func disableSleepPrevention() {
        if sleepAssertionActive {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionActive = false
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebViewManager: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let continuation = navigationContinuation {
            navigationContinuation = nil
            continuation.resume()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        if let continuation = navigationContinuation {
            navigationContinuation = nil
            continuation.resume(
                throwing: WebViewError.navigationFailed(error.localizedDescription)
            )
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        if let continuation = navigationContinuation {
            navigationContinuation = nil
            continuation.resume(
                throwing: WebViewError.navigationFailed(error.localizedDescription)
            )
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // 允许所有导航
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate

extension WebViewManager: WKUIDelegate {

    /// 拦截文件选择面板
    /// 如果有预设文件则直接返回（不弹对话框）
    /// 如果没有预设文件则弹出系统文件选择对话框
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        print("[WebView] runOpenPanel 被触发！pendingFiles=\(pendingUploadFiles.count)")
        if !pendingUploadFiles.isEmpty {
            let validFiles = pendingUploadFiles.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
            print("[WebView] 返回预设文件: \(validFiles.map { $0.lastPathComponent })")
            pendingUploadFiles = []
            completionHandler(validFiles.isEmpty ? nil : validFiles)
        } else {
            completionHandler(nil)
        }
    }

    /// 允许创建新的 WebView（应对 window.open）
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // 在当前 WebView 中加载（忽略弹窗）
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

// MARK: - WKScriptMessageHandler

extension WebViewManager: WKScriptMessageHandler {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let parsed = parseJSMessage(name: message.name, body: message.body)

        // 处理 waitForElement 的回调
        handleElementWaitCallback(message: parsed)

        // 转发给外部监听者
        jsMessageHandler?(parsed)
    }

    // MARK: 消息解析

    private func parseJSMessage(name: String, body: Any) -> JSBridgeMessage {
        guard let dict = body as? [String: Any] else {
            return .unknown
        }

        switch name {
        case "stepDone":
            let step = dict["step"] as? String ?? ""
            let status = dict["status"] as? String ?? ""
            return .stepDone(step: step, status: status)

        case "error":
            let step = dict["step"] as? String ?? ""
            let message = dict["message"] as? String ?? "未知错误"
            return .error(step: step, message: message)

        case "publishResult":
            let success = dict["success"] as? Bool ?? false
            let message = dict["message"] as? String ?? ""
            let url = dict["url"] as? String ?? ""
            return .publishResult(success: success, message: message, url: url)

        default:
            return .unknown
        }
    }

    // MARK: 元素等待回调处理

    private func handleElementWaitCallback(message: JSBridgeMessage) {
        switch message {
        case .stepDone(let step, let status):
            if step == "waitElement" && status == "found" {
                if let cont = elementContinuation {
                    elementContinuation = nil
                    waitingForSelector = nil
                    cont.resume()
                }
            }

        case .error(let step, let errMsg):
            if step == "waitElement" {
                if let cont = elementContinuation {
                    elementContinuation = nil
                    waitingForSelector = nil
                    cont.resume(throwing: WebViewError.waitForElementTimeout(errMsg))
                }
            }

        default:
            break
        }
    }
}

// MARK: - WeakMessageHandler（避免循环引用）

/// 弱引用包装，防止 WKUserContentController 对 WebViewManager 的强引用循环
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
