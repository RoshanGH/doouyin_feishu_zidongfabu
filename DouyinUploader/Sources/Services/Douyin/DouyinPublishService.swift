import Foundation
import AppKit

// MARK: - 发布错误类型

/// 抖音发布流程相关错误
enum DouyinPublishError: LocalizedError {
    case noCookiesFound(accountId: String)
    case invalidTaskMedia
    case uploadTimeout
    case publishTimeout
    case publishFailed(String)
    case localFilesNotProvided
    case localFileMissing(URL)
    case webViewError(String)
    case scheduleExpired
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .noCookiesFound(let id):
            return "账号 \(id) 未登录或 Cookie 已失效"
        case .invalidTaskMedia:
            return "任务媒体类型无效，无法发布"
        case .uploadTimeout:
            return "文件上传超时"
        case .publishTimeout:
            return "等待发布结果超时"
        case .publishFailed(let msg):
            return "发布失败：\(msg)"
        case .localFilesNotProvided:
            return "未提供本地文件路径"
        case .localFileMissing(let url):
            return "本地文件不存在：\(url.path)"
        case .webViewError(let msg):
            return "WebView 操作失败：\(msg)"
        case .scheduleExpired:
            return "定时发布时间已过期，请修改后重试"
        case .unknownError(let msg):
            return "未知错误：\(msg)"
        }
    }
}

// MARK: - 发布结果

/// 单次发布操作的结果
struct PublishResult {
    let success: Bool
    let message: String
    let publishedURL: String?
}

// MARK: - DouyinPublishServiceProtocol

/// 发布服务的抽象协议（便于测试中注入 mock）
protocol DouyinPublishServiceProtocol {
    /// 执行单条任务的发布流程
    /// - Parameters:
    ///   - task: 发布任务
    ///   - localFiles: 已下载到本地的媒体文件 URL 数组（顺序与 attachments 对应）
    /// - Returns: 发布结果
    func publishTask(task: PublishTask, localFiles: [URL]) async throws -> PublishResult
}

// MARK: - DouyinPublishService

/// 抖音自动化发布服务
/// 依赖 WebViewManager（通过 protocol 注入）、DouyinCookieManager、SelectorConfig
final class DouyinPublishService: DouyinPublishServiceProtocol {

    // MARK: - 依赖

    private let cookieManager: DouyinCookieManager
    private let selectorConfig: SelectorConfig
    private let webViewManagerFactory: @MainActor () -> WebViewManagerProtocol

    // MARK: - 超时常量（秒）

    private enum Timeout {
        static let pageLoad: TimeInterval = 30
        static let videoUpload: TimeInterval = 600   // 10 分钟
        static let imageUpload: TimeInterval = 120   // 2 分钟
        static let elementWait: TimeInterval = 30
        static let publishResult: TimeInterval = 60
    }

    // MARK: - 初始化

    init(
        cookieManager: DouyinCookieManager = DouyinCookieManager(),
        selectorConfig: SelectorConfig = SelectorConfig.defaultConfig,
        webViewManagerFactory: @escaping @MainActor () -> WebViewManagerProtocol = {
            let manager = WebViewManager()
            try? manager.setup()
            return manager
        }
    ) {
        self.cookieManager = cookieManager
        self.selectorConfig = selectorConfig
        self.webViewManagerFactory = webViewManagerFactory
    }

    // MARK: - DouyinPublishServiceProtocol

    func publishTask(task: PublishTask, localFiles: [URL]) async throws -> PublishResult {
        // 前置校验
        try validateTask(task, localFiles: localFiles)

        // 加载 Cookie
        guard let cookies = try cookieManager.loadCookies(uniqueId: task.douyinAccountId),
              !cookies.isEmpty else {
            throw DouyinPublishError.noCookiesFound(accountId: task.douyinAccountId)
        }

        // 在主线程创建 WebViewManager
        let webViewManager = await MainActor.run { webViewManagerFactory() }
        defer {
            Task { @MainActor in
                webViewManager.tearDown()
            }
        }

        // 根据任务类型分发
        if task.isVideo {
            return try await publishVideo(
                task: task,
                localFiles: localFiles,
                cookies: cookies,
                manager: webViewManager
            )
        } else if task.isImagePost {
            return try await publishImages(
                task: task,
                localFiles: localFiles,
                cookies: cookies,
                manager: webViewManager
            )
        } else {
            throw DouyinPublishError.invalidTaskMedia
        }
    }

    // MARK: - 视频发布流程

    private func publishVideo(
        task: PublishTask,
        localFiles: [URL],
        cookies: [HTTPCookie],
        manager: WebViewManagerProtocol
    ) async throws -> PublishResult {

        // 步骤 1：注入 Cookie 并加载上传页
        guard let uploadURL = URL(string: selectorConfig.common.uploadPageURL) else {
            throw DouyinPublishError.publishFailed("无效的上传页面 URL")
        }
        try await manager.injectCookiesAndLoad(cookies: cookies, url: uploadURL)
        try await manager.waitForNavigation(timeout: Timeout.pageLoad)

        try await randomDelay(min: 1.0, max: 2.0)

        // 步骤 2：处理"上次未发布的视频"弹窗（点击"放弃"）
        try await manager.evaluateJavaScript("""
            (function() {
                var btns = document.querySelectorAll('span, button, a');
                for (var i = 0; i < btns.length; i++) {
                    if (btns[i].textContent.trim() === '放弃') {
                        btns[i].click();
                        return 'dismissed';
                    }
                }
                return 'no_popup';
            })()
        """)
        try await randomDelay(min: 0.5, max: 1.0)

        // 步骤 3：触发文件上传
        // WKWebView 安全限制：JS 的 input.click() 不触发 runOpenPanel
        // 方案：通过 NSEvent 直接发送鼠标点击到 WebView，这是真正的用户事件
        await MainActor.run {
            manager.setPendingUploadFiles(localFiles)
        }

        // 获取上传 input 的页面坐标
        let coordJS = """
        (function() {
            var input = document.querySelector("div[class^='container'] input");
            if (input) {
                // 让 input 可见（有些页面 input 是隐藏的）
                input.style.opacity = '1';
                input.style.position = 'relative';
                input.style.width = '200px';
                input.style.height = '200px';
                input.style.zIndex = '99999';
                var rect = input.getBoundingClientRect();
                return JSON.stringify({x: rect.x + rect.width/2, y: rect.y + rect.height/2, w: rect.width, h: rect.height, found: 'input'});
            }
            return JSON.stringify({found: 'none'});
        })()
        """
        let coordResult = try await manager.evaluateJavaScript(coordJS) as? String ?? "{}"
        print("[Upload] 坐标结果: \(coordResult)")

        if let coordData = coordResult.data(using: .utf8),
           let coord = try? JSONSerialization.jsonObject(with: coordData) as? [String: Any],
           let found = coord["found"] as? String, found != "none" {

            let jsX = coord["x"] as? Double ?? 0
            let jsY = coord["y"] as? Double ?? 0

            // 通过 NSEvent 发送真实点击到 WebView
            await MainActor.run {
                if let wvm = manager as? WebViewManager,
                   let webView = wvm.webView,
                   let window = webView.window {

                    // 把窗口置前确保能接收事件
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)

                    // JS 坐标（左上角原点，Y 向下）→ NSView 坐标（左下角原点，Y 向上）
                    let viewHeight = webView.frame.height
                    let localPoint = NSPoint(x: jsX, y: viewHeight - jsY)

                    print("[Upload] 发送 NSEvent 到 WebView: local=(\(localPoint.x), \(localPoint.y))")

                    // 鼠标按下
                    if let mouseDown = NSEvent.mouseEvent(
                        with: .leftMouseDown,
                        location: webView.convert(localPoint, to: nil), // 转为窗口坐标
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 1,
                        pressure: 1.0
                    ) {
                        webView.mouseDown(with: mouseDown)
                    }

                    usleep(100_000) // 100ms

                    // 鼠标松开
                    if let mouseUp = NSEvent.mouseEvent(
                        with: .leftMouseUp,
                        location: webView.convert(localPoint, to: nil),
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 1,
                        pressure: 0.0
                    ) {
                        webView.mouseUp(with: mouseUp)
                    }
                }
            }
        } else {
            print("[Upload] 未找到上传 input 元素")
        }

        // 等待 runOpenPanel 被触发并返回文件
        try await randomDelay(min: 3.0, max: 5.0)

        // 步骤 4：等待页面跳转到发布信息页
        var waitCount = 0
        let maxWait = 180 // 最多等 180 秒
        while waitCount < maxWait {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            waitCount += 3

            let urlCheck = try await manager.evaluateJavaScript("window.location.href") as? String ?? ""
            if urlCheck.contains("publish") || urlCheck.contains("post/video") {
                break
            }

            // 每 15 秒记录一次状态
            if waitCount % 15 == 0 {
                let pageTitle = try await manager.evaluateJavaScript("document.title") as? String ?? ""
                print("[Upload] 等待中... URL=\(urlCheck.prefix(60)) title=\(pageTitle.prefix(30))")
            }
        }

        if waitCount >= maxWait {
            throw DouyinPublishError.uploadTimeout
        }

        try await randomDelay(min: 1.0, max: 2.0)

        // 步骤 5：注入发布参数并执行信息填写+发布脚本
        await MainActor.run {
            manager.setPendingUploadFiles(localFiles)
        }
        let publishResult = try await runVideoPublishScript(task: task, manager: manager)

        return publishResult
    }

    // MARK: - 图文发布流程

    private func publishImages(
        task: PublishTask,
        localFiles: [URL],
        cookies: [HTTPCookie],
        manager: WebViewManagerProtocol
    ) async throws -> PublishResult {

        // 步骤 1：注入 Cookie 并加载上传页
        guard let uploadURL = URL(string: selectorConfig.common.uploadPageURL) else {
            throw DouyinPublishError.publishFailed("无效的上传页面 URL")
        }
        try await manager.injectCookiesAndLoad(cookies: cookies, url: uploadURL)
        try await manager.waitForNavigation(timeout: Timeout.pageLoad)

        // 随机延迟
        try await randomDelay(min: 0.8, max: 1.5)

        // 步骤 2：预设待上传图片文件
        await MainActor.run {
            manager.setPendingUploadFiles(localFiles)
        }

        // 步骤 3：注入发布参数并执行图文发布脚本
        let publishResult = try await runImagePublishScript(task: task, localFiles: localFiles, manager: manager)

        return publishResult
    }

    // MARK: - 执行视频发布脚本

    private func runVideoPublishScript(
        task: PublishTask,
        manager: WebViewManagerProtocol
    ) async throws -> PublishResult {

        // 构建 JS 参数
        let params = buildVideoParams(task: task)
        let paramsJSON = try encodeToJSON(params)

        // 注入参数
        let injectScript = "window.publishVideoParams = \(paramsJSON);"
        try await manager.evaluateJavaScript(injectScript)

        // 加载音乐选择脚本（注册 window.selectMusic 函数）
        let musicScript = try loadBundleJS(named: "douyin_music_select")
        try await manager.evaluateJavaScript(musicScript)

        // 加载并执行发布脚本
        let publishScript = try loadBundleJS(named: "douyin_video_publish")
        try await manager.evaluateJavaScript(publishScript)

        // 等待发布结果（通过 JS bridge 回调）
        return try await waitForPublishResult(
            manager: manager,
            timeout: Timeout.publishResult + Timeout.videoUpload
        )
    }

    // MARK: - 执行图文发布脚本

    private func runImagePublishScript(
        task: PublishTask,
        localFiles: [URL],
        manager: WebViewManagerProtocol
    ) async throws -> PublishResult {

        // 构建 JS 参数
        let params = buildImageParams(task: task, imageCount: localFiles.count)
        let paramsJSON = try encodeToJSON(params)

        // 注入参数
        let injectScript = "window.publishImageParams = \(paramsJSON);"
        try await manager.evaluateJavaScript(injectScript)

        // 加载音乐选择脚本（注册 window.selectMusic 函数）
        let musicScript = try loadBundleJS(named: "douyin_music_select")
        try await manager.evaluateJavaScript(musicScript)

        // 加载并执行发布脚本
        let publishScript = try loadBundleJS(named: "douyin_image_publish")
        try await manager.evaluateJavaScript(publishScript)

        // 等待发布结果
        return try await waitForPublishResult(
            manager: manager,
            timeout: Timeout.publishResult + Timeout.imageUpload
        )
    }

    // MARK: - 等待发布结果

    private func waitForPublishResult(
        manager: WebViewManagerProtocol,
        timeout: TimeInterval
    ) async throws -> PublishResult {

        // 使用 actor-safe 的 continuation 包装
        // onJSMessage 是 @MainActor 方法，需要在主线程注册
        return try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox(continuation: continuation)

            Task { @MainActor in
                manager.onJSMessage { message in
                    guard !box.resolved else { return }

                    switch message {
                    case .publishResult(let success, let msg, let url):
                        box.resolved = true
                        let result = PublishResult(
                            success: success,
                            message: msg,
                            publishedURL: url.isEmpty ? nil : url
                        )
                        if success {
                            box.continuation.resume(returning: result)
                        } else {
                            box.continuation.resume(
                                throwing: DouyinPublishError.publishFailed(msg)
                            )
                        }

                    case .error(_, let msg):
                        box.resolved = true
                        box.continuation.resume(
                            throwing: DouyinPublishError.webViewError(msg)
                        )

                    default:
                        break
                    }
                }
            }

            // 超时保护（在非 actor 上下文中运行）
            Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !box.resolved {
                    box.resolved = true
                    box.continuation.resume(throwing: DouyinPublishError.publishTimeout)
                }
            }
        }
    }

    // MARK: - 模拟鼠标点击

    /// 用 CGEvent 在 WebView 窗口内模拟真实鼠标点击
    /// - Parameters:
    ///   - manager: WebViewManager（获取窗口位置）
    ///   - jsX: JS 中元素的 x 坐标（相对视口）
    ///   - jsY: JS 中元素的 y 坐标（相对视口）
    @MainActor
    private func simulateMouseClick(manager: WebViewManagerProtocol, jsX: Double, jsY: Double) {
        // 获取 WebView 所在窗口的屏幕坐标
        guard let webViewManager = manager as? WebViewManager,
              let webView = webViewManager.webView,
              let window = webView.window else {
            print("[Upload] 无法获取 WebView 窗口，跳过鼠标模拟")
            return
        }

        // 将 JS 坐标（视口左上角为原点，Y 向下）转为 macOS 屏幕坐标（左下角为原点，Y 向上）
        let windowFrame = window.frame
        let webViewFrame = webView.convert(webView.bounds, to: nil)
        let screenX = windowFrame.origin.x + webViewFrame.origin.x + jsX
        let screenY = windowFrame.origin.y + webViewFrame.origin.y + (webViewFrame.height - jsY) // 翻转 Y

        let point = CGPoint(x: screenX, y: NSScreen.main!.frame.height - screenY) // CGEvent 用的是左上角原点

        print("[Upload] 模拟点击屏幕坐标: (\(point.x), \(point.y))")

        // 模拟鼠标按下 + 松开
        if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            mouseDown.post(tap: .cghidEventTap)
        }
        usleep(100_000) // 100ms
        if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - 参数构建

    private func buildVideoParams(task: PublishTask) -> [String: Any] {
        var params: [String: Any] = [
            "content": task.fullContent,
            "hasSchedule": task.scheduledTime != nil,
            "hasMusic": task.hasMusic,
            "isVideo": true,
            "stepTimeout": Int(Timeout.elementWait * 1000),
            "uploadTimeout": Int(Timeout.videoUpload * 1000),
            "resultTimeout": Int(Timeout.publishResult * 1000)
        ]

        if let scheduledTime = task.scheduledTime {
            params["scheduleTime"] = formatScheduleTime(scheduledTime)
        }

        if let musicName = task.musicName, task.hasMusic {
            params["musicName"] = musicName
        }

        return params
    }

    private func buildImageParams(task: PublishTask, imageCount: Int) -> [String: Any] {
        var params: [String: Any] = [
            "title": task.title ?? "",
            "content": task.fullContent,
            "imageCount": imageCount,
            "hasSchedule": task.scheduledTime != nil,
            "hasMusic": task.hasMusic,
            "isVideo": false,
            "stepTimeout": Int(Timeout.elementWait * 1000),
            "uploadTimeout": Int(Timeout.imageUpload * 1000),
            "resultTimeout": Int(Timeout.publishResult * 1000)
        ]

        if let scheduledTime = task.scheduledTime {
            params["scheduleTime"] = formatScheduleTime(scheduledTime)
        }

        if let musicName = task.musicName, task.hasMusic {
            params["musicName"] = musicName
        }

        return params
    }

    // MARK: - 工具方法

    /// 将任务参数字典编码为 JSON 字符串
    private func encodeToJSON(_ params: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: params,
            options: [.sortedKeys]
        )
        guard let json = String(data: data, encoding: .utf8) else {
            throw DouyinPublishError.unknownError("JSON 编码失败")
        }
        return json
    }

    /// 格式化定时发布时间为抖音所需格式
    private func formatScheduleTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    /// 从 Bundle 加载 JS 脚本内容
    private func loadBundleJS(named name: String) throws -> String {
        // 尝试 Bundle.module（Swift Package 资源）
        if let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "JS") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        if let url = Bundle.module.url(forResource: name, withExtension: "js") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "js") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        throw WebViewError.scriptLoadFailed(name)
    }

    /// 随机延迟（模拟人工操作节奏）
    private func randomDelay(min: Double, max: Double) async throws {
        let delay = min + Double.random(in: 0...(max - min))
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    // MARK: - 前置校验

    private func validateTask(_ task: PublishTask, localFiles: [URL]) throws {
        // 任务媒体类型必须有效
        guard task.isValid else {
            throw DouyinPublishError.invalidTaskMedia
        }

        // 必须提供本地文件
        guard !localFiles.isEmpty else {
            throw DouyinPublishError.localFilesNotProvided
        }

        // 所有本地文件必须存在
        for fileURL in localFiles {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw DouyinPublishError.localFileMissing(fileURL)
            }
        }

        // 检查定时时间是否已过期（仅视频任务有 buffer，图文不允许过期）
        if task.isScheduleExpired {
            throw DouyinPublishError.scheduleExpired
        }
    }
}

// MARK: - ContinuationBox（线程安全的 continuation 包装）

/// 用于在非结构化 Task 和闭包中安全传递 CheckedContinuation
/// 因为 continuation 只能 resume 一次，用 resolved 标志位防止重复
private final class ContinuationBox<T>: @unchecked Sendable {
    let continuation: CheckedContinuation<T, Error>
    var resolved: Bool = false

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }
}
