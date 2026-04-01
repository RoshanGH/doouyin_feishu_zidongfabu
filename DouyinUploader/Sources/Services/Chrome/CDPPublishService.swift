import Foundation
import AppKit
import UserNotifications

/// 基于 Chrome CDP 协议的抖音发布服务
final class CDPPublishService {

    private let chromeManager = ChromeManager.shared
    private let cookieManager: DouyinCookieManager
    private let settings: AppSettings

    var onLog: ((LogLevel, String) -> Void)?

    /// 操作间隔（秒）
    private let stepDelay: UInt64 = 2_000_000_000 // 2 秒

    init(cookieManager: DouyinCookieManager = DouyinCookieManager(), settings: AppSettings = SettingsManager().load()) {
        self.cookieManager = cookieManager
        self.settings = settings
    }

    // MARK: - 批量发布（同一账号复用浏览器，逐条下载+发布）

    func publishBatch(
        accountId: String,
        tasks: [PublishTask],
        downloadFiles: @escaping (PublishTask) async throws -> [URL],
        onTaskResult: @escaping (PublishTask, Result<PublishResult, Error>) async -> Void
    ) async {
        guard chromeManager.isInstalled else {
            for task in tasks { await onTaskResult(task, .failure(ChromeError.notInstalled)) }
            return
        }

        log(.info, "启动 Chrome...")

        let process: Process
        let port: Int
        do {
            (process, port) = try await chromeManager.launchChrome(accountId: accountId, headless: false)
        } catch {
            log(.error, "Chrome 启动失败: \(error.localizedDescription)")
            for task in tasks { await onTaskResult(task, .failure(error)) }
            return
        }
        defer {
            process.terminate()
            process.waitUntilExit()
            log(.info, "Chrome 进程已关闭")
        }

        let cdp: CDPClient
        do {
            cdp = try await connectCDP(port: port)
        } catch {
            log(.error, "CDP 连接失败: \(error.localizedDescription)")
            for task in tasks { await onTaskResult(task, .failure(error)) }
            return
        }
        defer { cdp.disconnect() }

        // 先清空 Chrome 中的旧 Cookie，再注入当前账号的 Cookie（确保账号隔离）
        let _ = try? await cdp.send("Network.clearBrowserCookies")
        do {
            try await injectCookies(cdp: cdp, accountId: accountId)
        } catch {
            log(.error, "Cookie 注入失败: \(error.localizedDescription)")
            for task in tasks { await onTaskResult(task, .failure(error)) }
            return
        }

        // 创建 AI Agent（如果配置了 AI Key 且模式不是 off）
        let aiAgent: AIAgent? = {
            guard settings.aiMode != .off else { return nil }
            guard let apiKey = try? KeychainService.loadString(key: KeychainService.aiAPIKeyStorageKey),
                  !apiKey.isEmpty else { return nil }
            let config = AIConfig(baseURL: settings.aiBaseURL, apiKey: apiKey, model: settings.aiModel)
            let driver = CDPDriverImpl(client: cdp)
            let agent = AIAgent(config: config, driver: driver)
            agent.onLog = onLog
            return agent
        }()
        if aiAgent != nil {
            log(.info, "AI 模式已启用（\(settings.aiMode.displayName)）")
        }

        let musicDownloader = MusicDownloader()
        musicDownloader.onLog = onLog
        let merger = AudioVideoMerger()
        merger.onLog = onLog

        // 逐条执行（每条先下载再发布）
        for (index, task) in tasks.enumerated() {
            log(.info, "[\(index + 1)/\(tasks.count)] 开始发布: \(task.displayName)")

            // 定时发布时间二次校验（概览页停留过久可能过期）
            if task.isScheduleExpired {
                log(.warning, "定时发布时间已过期，跳过此任务")
                await onTaskResult(task, .failure(DouyinPublishError.scheduleExpired))
                continue
            }

            do {
                // 下载素材
                var localFiles: [URL] = try await downloadFiles(task)

                // 如果是视频任务且有音乐，先下载音乐并合并
                if task.isVideo && task.hasMusic, let musicName = task.musicName, let videoFile = localFiles.first {
                    log(.info, "--- 音乐融合流程 ---")

                    // 下载音乐（可能抛 cookieExpired）
                    if let musicFile = try await musicDownloader.downloadMusic(cdp: cdp, musicName: musicName) {
                        do {
                            let mergedVideo = try await merger.merge(videoURL: videoFile, musicURL: musicFile)
                            localFiles = [mergedVideo]
                            log(.info, "音乐融合完成，将使用合并视频上传")
                        } catch {
                            log(.error, "音视频合并失败: \(error.localizedDescription)")
                        }
                        try? FileManager.default.removeItem(at: musicFile)
                    } else {
                        log(.warning, "音乐下载失败，使用原始视频继续发布")
                    }

                    log(.info, "--- 音乐融合流程结束 ---")
                }

                // 发布
                let result: PublishResult
                if task.isVideo {
                    result = try await publishVideo(cdp: cdp, task: task, localFiles: localFiles, aiAgent: aiAgent)
                } else if task.isImagePost {
                    result = try await publishImages(cdp: cdp, task: task, localFiles: localFiles, aiAgent: aiAgent)
                } else {
                    throw DouyinPublishError.invalidTaskMedia
                }
                await onTaskResult(task, .success(result))
            } catch {
                await onTaskResult(task, .failure(error))

                // 登录过期：跳过该账号所有剩余任务
                if let pubError = error as? DouyinPublishError, isCookieExpiredError(pubError) {
                    log(.error, "⚠️ 账号 \(accountId) 登录已过期，跳过该账号所有剩余任务")
                    for remainingTask in tasks.suffix(from: index + 1) {
                        await onTaskResult(remainingTask, .failure(DouyinPublishError.cookieExpired(accountId: accountId)))
                    }
                    return
                }
            }

            // 任务间等待
            if index < tasks.count - 1 {
                let wait = settings.taskIntervalMin + Double.random(in: 0...(settings.taskIntervalMax - settings.taskIntervalMin))
                log(.info, "等待 \(Int(wait)) 秒后继续...")
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }

        // 执行完毕，从 Chrome 回收最新 Cookie（服务器可能已续期）
        await refreshCookies(cdp: cdp, accountId: accountId)
    }

    // MARK: - Cookie 续期

    /// 从 Chrome 提取最新 Cookie 存回本地（服务器在操作过程中可能已续期）
    private func refreshCookies(cdp: CDPClient, accountId: String) async {
        do {
            let rawCookies = try await cdp.getCookies(domain: "douyin.com")
            var httpCookies: [HTTPCookie] = []

            for raw in rawCookies {
                guard let name = raw["name"] as? String,
                      let value = raw["value"] as? String,
                      let domain = raw["domain"] as? String else { continue }

                var props: [HTTPCookiePropertyKey: Any] = [
                    .name: name,
                    .value: value,
                    .domain: domain,
                    .path: raw["path"] as? String ?? "/"
                ]
                if let expires = raw["expires"] as? Double, expires > 0 {
                    props[.expires] = Date(timeIntervalSince1970: expires)
                }
                if let cookie = HTTPCookie(properties: props) {
                    httpCookies.append(cookie)
                }
            }

            if !httpCookies.isEmpty {
                try cookieManager.saveCookies(uniqueId: accountId, cookies: httpCookies)
                log(.info, "Cookie 已续期（\(httpCookies.count) 个），下次执行可继续使用")
            }
        } catch {
            log(.warning, "Cookie 回收失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 单条发布

    func publishTask(task: PublishTask, localFiles: [URL]) async throws -> PublishResult {
        guard chromeManager.isInstalled else { throw ChromeError.notInstalled }

        log(.info, "启动 Chrome...")
        let (process, port) = try await chromeManager.launchChrome(accountId: task.douyinAccountId, headless: false)
        defer {
            process.terminate()
            process.waitUntilExit()
            log(.info, "Chrome 进程已关闭")
        }

        let cdp = try await connectCDP(port: port)
        defer { cdp.disconnect() }

        try await injectCookies(cdp: cdp, accountId: task.douyinAccountId)

        if task.isVideo {
            return try await publishVideo(cdp: cdp, task: task, localFiles: localFiles)
        } else if task.isImagePost {
            return try await publishImages(cdp: cdp, task: task, localFiles: localFiles)
        } else {
            throw DouyinPublishError.invalidTaskMedia
        }
    }

    // MARK: - CDP 连接

    private func connectCDP(port: Int) async throws -> CDPClient {
        log(.info, "等待 Chrome 就绪（端口 \(port)）...")
        var wsURL: String?
        for attempt in 1...15 {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                wsURL = try await chromeManager.getPageWebSocketURL(port: port)
                break
            } catch {
                if attempt <= 3 || attempt % 3 == 0 { log(.info, "等待 CDP... (\(attempt * 2)s)") }
                if attempt == 15 { throw error }
            }
        }
        guard let wsURL else { throw ChromeError.launchTimeout }
        log(.info, "CDP WebSocket: \(wsURL.prefix(60))...")
        let cdp = CDPClient()
        try await cdp.connect(wsURL: wsURL)
        log(.info, "CDP 连接成功")
        return cdp
    }

    // MARK: - Cookie

    private func injectCookies(cdp: CDPClient, accountId: String) async throws {
        guard let cookies = try cookieManager.loadCookies(uniqueId: accountId), !cookies.isEmpty else {
            throw DouyinPublishError.noCookiesFound(accountId: accountId)
        }
        log(.info, "注入 \(cookies.count) 个 Cookie...")
        let list = cookies.map { (name: $0.name, value: $0.value, domain: $0.domain, path: $0.path) }
        try await cdp.setCookies(list)
    }

    // MARK: - 登录过期检测

    private func isCookieExpiredError(_ error: DouyinPublishError) -> Bool {
        if case .cookieExpired = error { return true }
        if case .noCookiesFound = error { return true }
        return false
    }

    /// 检测页面是否跳转到了登录页（Cookie 过期）
    /// 过期时直接抛错，由 publishBatch 跳过该账号的所有剩余任务
    private func checkLoginStatus(cdp: CDPClient, accountId: String) async throws {
        let currentURL = try await cdp.getCurrentURL()

        let isLoginPage = currentURL.contains("sso.douyin.com")
            || currentURL.contains("/login")
            || currentURL.contains("passport")

        let hasLoginPrompt = (try? await cdp.evaluate("""
            (function() {
                var t = document.body ? document.body.innerText : '';
                return t.indexOf('扫码登录') !== -1 || t.indexOf('手机号登录') !== -1 || t.indexOf('请登录') !== -1;
            })()
        """) as? Bool) ?? false

        guard isLoginPage || hasLoginPrompt else { return }

        throw DouyinPublishError.cookieExpired(accountId: accountId)
    }

    // MARK: - 验证码检测

    /// 检测弹窗/验证码/异常 — AI 模式用截图分析，fallback 用旧的关键词匹配
    private func checkVerification(cdp: CDPClient, aiAgent: AIAgent? = nil, accountId: String = "") async throws {
        // AI 模式：截图让 AI 判断
        if let agent = aiAgent, settings.aiMode != .off {
            do {
                let handled = try await agent.checkAndHandlePopup(taskDescription: "发布任务")
                if handled {
                    log(.info, "AI 自动处理了弹窗")
                    // 处理后再检查一次（可能有多层弹窗）
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    let _ = try await agent.checkAndHandlePopup(taskDescription: "发布任务")
                }
                return
            } catch let error as AIAgentError {
                switch error {
                case .captchaDetected(let msg):
                    log(.warning, "⚠️ AI 检测到验证码：\(msg)")
                    await notifyUserForVerification()
                    // 无限等待用户处理
                    try await waitForCaptchaResolution(cdp: cdp, aiAgent: agent)
                    return
                case .loginExpired:
                    throw DouyinPublishError.cookieExpired(accountId: accountId)
                default:
                    log(.warning, "AI 弹窗检测异常，回退到旧逻辑: \(error.localizedDescription)")
                }
            } catch {
                log(.warning, "AI 不可用，回退到旧逻辑: \(error.localizedDescription)")
            }
        }

        // Fallback：旧的关键词匹配逻辑
        try await checkVerificationLegacy(cdp: cdp)
    }

    /// AI 模式下等待验证码完成
    private func waitForCaptchaResolution(cdp: CDPClient, aiAgent: AIAgent) async throws {
        var seconds = 0
        while true {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            seconds += 3

            // 用 AI 再次检查验证码是否消失
            do {
                let result = try await aiAgent.analyzePage(
                    taskDescription: "发布任务",
                    currentStep: "等待验证码完成"
                )
                if result.status != .captcha {
                    log(.info, "✅ 验证码已通过（等待了 \(seconds)s）")
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    return
                }
            } catch {
                // AI 失败时 fallback 到旧方式检查
                let still = try await checkVerificationKeywords(cdp: cdp)
                if !still {
                    log(.info, "✅ 验证码已通过（等待了 \(seconds)s）")
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    return
                }
            }

            if seconds % 30 == 0 {
                log(.info, "⏳ 仍在等待验证码处理...（已等待 \(seconds)s）")
                await notifyUserForVerification()
            }
        }
    }

    /// 旧逻辑：JS 关键词匹配检测验证码
    private func checkVerificationLegacy(cdp: CDPClient) async throws {
        let hasV = try await checkVerificationKeywords(cdp: cdp)
        guard hasV else { return }

        log(.warning, "⚠️ 检测到验证码！任务已暂停，请在 Chrome 窗口中手动完成验证")
        await notifyUserForVerification()

        var seconds = 0
        while true {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            seconds += 2

            let still = try await checkVerificationKeywords(cdp: cdp)
            if !still {
                log(.info, "✅ 验证码已通过（等待了 \(seconds)s）")
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return
            }

            if seconds % 30 == 0 {
                log(.info, "⏳ 仍在等待验证码处理...（已等待 \(seconds)s）")
                await notifyUserForVerification()
            }
        }
    }

    /// 检测页面中是否包含验证码关键词（提取为独立方法，供多处调用）
    private func checkVerificationKeywords(cdp: CDPClient) async throws -> Bool {
        return (try? await cdp.evaluate("""
            (function() {
                var t = document.body ? document.body.innerText : '';
                var dialogs = document.querySelectorAll('[role="dialog"], .semi-modal, [class*="modal"], [class*="captcha"], [class*="verify"]');
                for (var i = 0; i < dialogs.length; i++) { t += ' ' + dialogs[i].innerText; }
                var frames = document.querySelectorAll('iframe');
                for (var j = 0; j < frames.length; j++) {
                    try { t += ' ' + frames[j].contentDocument.body.innerText; } catch(e) {}
                }
                var keywords = ['滑动', '拼图', '验证码', '请完成验证', '安全验证', '点击完成验证', '向右拖动'];
                for (var k = 0; k < keywords.length; k++) {
                    if (t.indexOf(keywords[k]) !== -1) return true;
                }
                return false;
            })()
        """) as? Bool) ?? false
    }

    /// 三重提醒：Dock 弹跳 + 系统通知 + 声音
    @MainActor
    private func notifyUserForVerification() {
        // 1. Dock 图标持续弹跳（直到用户切到 App）
        NSApp.requestUserAttention(.criticalRequest)

        // 2. 系统通知
        let content = UNMutableNotificationContent()
        content.title = "⚠️ 抖音验证码"
        content.body = "抖音触发了验证码，请切换到 Chrome 窗口手动完成验证"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "captcha-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

        // 3. 系统提示音
        NSSound.beep()
    }

    // MARK: - 视频发布

    private func publishVideo(cdp: CDPClient, task: PublishTask, localFiles: [URL], aiAgent: AIAgent? = nil) async throws -> PublishResult {
        guard let videoFile = localFiles.first else { throw DouyinPublishError.localFilesNotProvided }

        // 1. 加载上传页
        log(.info, "加载抖音上传页...")
        try await cdp.navigate(to: "https://creator.douyin.com/creator-micro/content/upload")
        try await sleep()

        // 检测登录是否过期（Cookie 失效会跳转到登录页）
        try await checkLoginStatus(cdp: cdp, accountId: task.douyinAccountId)
        try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)

        // 登录恢复后重新导航到上传页
        let urlAfterCheck = try await cdp.getCurrentURL()
        if !urlAfterCheck.contains("upload") {
            try await cdp.navigate(to: "https://creator.douyin.com/creator-micro/content/upload")
            try await sleep()
        }

        // 2. 处理"上次未发布"弹窗
        let _ = try await cdp.evaluate("(function(){var b=document.querySelectorAll('span,button,a');for(var i=0;i<b.length;i++){if(b[i].textContent.trim()==='放弃'){b[i].click();return'ok'}}return'no'})()")
        try await sleep()

        // 3. 上传文件
        log(.info, "上传视频文件: \(videoFile.lastPathComponent)")
        try await cdp.setFileInputFiles(
            selector: "div[class^='container'] input, input[type='file']",
            files: [videoFile.path]
        )
        try await sleep()
        try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)

        // 4. 等待跳转到发布信息页
        log(.info, "等待视频处理...")
        try await cdp.waitForURL(containing: "publish", timeout: 180)
        log(.info, "已进入发布信息页")
        try await sleep(2)
        try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)

        // 5. 填写标题
        let titleText = (task.title ?? task.content).prefix(30).description
        await fillTitle(cdp: cdp, title: titleText)
        try await sleep()
        try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)

        // 6. 填写文案和话题
        await fillDescription(cdp: cdp, content: task.content, tags: task.tags)
        try await sleep()
        try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)

        // 7. 设置封面（失败则截图诊断 + 抛错阻断发布）
        let coverOk = await setCover(cdp: cdp, aiAgent: aiAgent)
        if !coverOk {
            // 截图保存到本地，方便排查
            await saveDebugScreenshot(cdp: cdp, name: "cover_failed")
            throw DouyinPublishError.publishFailed("设置封面失败，诊断截图已保存到 debug-logs/")
        }
        try await sleep()
        try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)

        // 8. 定时发布
        if let time = task.scheduledTime {
            log(.info, "设置定时发布...")
            await setScheduleTime(cdp: cdp, time: time)
            try await sleep()
            try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)
        }

        // 9. 点击发布
        log(.info, "点击发布...")
        return try await clickPublishAndWait(cdp: cdp, aiAgent: aiAgent)
    }

    // MARK: - 图文发布

    private func publishImages(cdp: CDPClient, task: PublishTask, localFiles: [URL], aiAgent: AIAgent? = nil) async throws -> PublishResult {
        log(.info, "加载抖音上传页...")
        try await cdp.navigate(to: "https://creator.douyin.com/creator-micro/content/upload")
        try await sleep()

        // 检测登录是否过期
        try await checkLoginStatus(cdp: cdp, accountId: task.douyinAccountId)
        try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)

        // 登录恢复后重新导航到上传页
        let urlAfterCheck = try await cdp.getCurrentURL()
        if !urlAfterCheck.contains("upload") {
            try await cdp.navigate(to: "https://creator.douyin.com/creator-micro/content/upload")
            try await sleep()
        }

        // 切换图文模式
        log(.info, "切换到图文发布模式...")
        let _ = try await cdp.evaluate("(function(){var t=document.querySelectorAll('span,div,a');for(var i=0;i<t.length;i++){if(t[i].textContent.trim()==='发布图文'){t[i].click();return'ok'}}return'no'})()")
        try await sleep(2)
        try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)

        // 上传图片
        log(.info, "上传 \(localFiles.count) 张图片...")
        try await cdp.setFileInputFiles(
            selector: "div[class^='container'] input[accept*='image'], div[class^='container'] input, input[type='file']",
            files: localFiles.map { $0.path }
        )
        try await sleep()
        try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)

        try await cdp.waitForURL(containing: "publish", timeout: 120)
        log(.info, "已进入发布信息页")
        try await sleep(2)
        try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)

        // 标题
        if let title = task.title, !title.isEmpty {
            await fillTitle(cdp: cdp, title: String(title.prefix(30)))
            try await sleep()
            try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)
        }

        // 文案 + 话题
        await fillDescription(cdp: cdp, content: task.content, tags: task.tags)
        try await sleep()
        try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)

        // 定时
        if let time = task.scheduledTime {
            log(.info, "设置定时发布...")
            await setScheduleTime(cdp: cdp, time: time)
            try await sleep()
            try await checkVerification(cdp: cdp, aiAgent: aiAgent, accountId: task.douyinAccountId)
        }

        log(.info, "点击发布...")
        return try await clickPublishAndWait(cdp: cdp, aiAgent: aiAgent)
    }

    // MARK: - 填写标题

    /// 在 input[placeholder*="标题"] 中填写标题，前后加空格
    private func fillTitle(cdp: CDPClient, title: String) async {
        let escaped = title.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")

        log(.info, "填写标题: \(title.prefix(20))...")
        let _ = try? await cdp.evaluate("""
            (function() {
                var input = document.querySelector('input[placeholder*="标题"][placeholder*="作品"]');
                if (!input) input = document.querySelector('input[placeholder*="标题"]');
                if (!input) return 'no_input';
                input.focus();
                // 用 nativeInputValueSetter 兼容 React
                var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
                setter.call(input, ' \(escaped) ');
                input.dispatchEvent(new Event('input', {bubbles: true}));
                input.dispatchEvent(new Event('change', {bubbles: true}));
                return 'filled';
            })()
        """)
    }

    // MARK: - 填写文案和话题

    /// 在 contenteditable 编辑器中填写文案，然后逐个输入话题（#tag + 空格）
    /// 参考 social-auto-upload: keyboard.type(description) + 逐个 " #tag" + Space
    private func fillDescription(cdp: CDPClient, content: String, tags: [String]) async {
        log(.info, "填写文案和话题...")

        // 1. 点击编辑器获取焦点
        let _ = try? await cdp.evaluate("""
            (function() {
                var editor = document.querySelector('.zone-container[contenteditable="true"]');
                if (!editor) editor = document.querySelector('[contenteditable="true"]');
                if (editor) { editor.click(); editor.focus(); return 'focused'; }
                return 'no_editor';
            })()
        """)
        try? await Task.sleep(nanoseconds: stepDelay)

        // 2. 清空现有内容 (Ctrl+A + Delete)
        let _ = try? await cdp.send("Input.dispatchKeyEvent", params: [
            "type": "keyDown", "key": "a", "code": "KeyA", "modifiers": 2
        ])
        let _ = try? await cdp.send("Input.dispatchKeyEvent", params: [
            "type": "keyUp", "key": "a", "code": "KeyA", "modifiers": 2
        ])
        try? await Task.sleep(nanoseconds: stepDelay)

        let _ = try? await cdp.send("Input.dispatchKeyEvent", params: [
            "type": "keyDown", "key": "Delete", "code": "Delete"
        ])
        let _ = try? await cdp.send("Input.dispatchKeyEvent", params: [
            "type": "keyUp", "key": "Delete", "code": "Delete"
        ])
        try? await Task.sleep(nanoseconds: stepDelay)

        // 3. 逐字符输入文案
        let segments = splitContent(content, maxLength: 50)
        for segment in segments {
            let _ = try? await cdp.send("Input.insertText", params: ["text": segment])
            try? await Task.sleep(nanoseconds: stepDelay)
        }

        // 4. 逐个输入话题标签（一行一个）
        // 流程：空格 → #标签 → 等1秒 → 回车（选第一个结果+换行）
        for tag in tags {
            let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
            if cleanTag.isEmpty { continue }

            // 空格
            let _ = try? await cdp.send("Input.insertText", params: ["text": " "])
            try? await Task.sleep(nanoseconds: 500_000_000)

            // 标签（如果用户已经带了#就不再加）——逐字符输入，让搜索下拉框正确触发
            let tagText = cleanTag.hasPrefix("#") ? cleanTag : "#\(cleanTag)"
            for char in tagText {
                let _ = try? await cdp.send("Input.insertText", params: ["text": String(char)])
                try? await Task.sleep(nanoseconds: 200_000_000) // 每字符间隔 200ms
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 等1秒让搜索结果出现

            // 回车（选第一个结果 + 换行）
            let _ = try? await cdp.send("Input.dispatchKeyEvent", params: [
                "type": "keyDown", "key": "Enter", "code": "Enter", "windowsVirtualKeyCode": 13
            ])
            let _ = try? await cdp.send("Input.dispatchKeyEvent", params: [
                "type": "keyUp", "key": "Enter", "code": "Enter", "windowsVirtualKeyCode": 13
            ])
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// 将长文本分段
    private func splitContent(_ content: String, maxLength: Int) -> [String] {
        var segments: [String] = []
        var remaining = content
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(maxLength, remaining.count))
            segments.append(String(remaining[remaining.startIndex..<end]))
            remaining = String(remaining[end...])
        }
        return segments
    }

    // MARK: - 设置封面

    /// 点击「选择封面」→ 等弹窗加载 → 点击「完成」
    /// - Returns: 是否成功设置封面
    @discardableResult
    private func setCover(cdp: CDPClient, aiAgent: AIAgent? = nil) async -> Bool {
        log(.info, "设置封面...")

        // AI 模式：AI 点「选择封面」打开弹窗，「完成」按钮用 JS 匹配（弹窗内结构稳定）
        if let agent = aiAgent, settings.aiMode == .full {
            do {
                try await agent.safeClick(
                    elementDescription: "找到页面上的「选择封面」按钮（竖封面或横封面都行，不是「设置封面」标题文字），返回按钮区域的中心坐标",
                    verifyDescription: "封面设置弹窗已打开"
                )
                log(.info, "AI 成功点击「选择封面」，等待弹窗加载...")
                try await Task.sleep(nanoseconds: 3_000_000_000)

                // 弹窗内的「完成」按钮用 JS 匹配（比 AI 更快更准）
                let clicked = (try? await clickButtonByText(cdp: cdp, text: "完成", maxWait: 5)) ?? false
                if clicked {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    log(.info, "封面设置完成（AI + JS）")
                    return true
                } else {
                    log(.warning, "AI 打开了封面弹窗但找不到「完成」按钮")
                }
            } catch {
                log(.warning, "AI 封面设置失败，回退到旧逻辑: \(error.localizedDescription)")
            }
        }

        // Fallback：多策略逐个尝试点击封面卡片
        // 封面区域是两个大卡片（竖封面/横封面），里面有缩略图+「选择封面」文字
        let coverClicked = (try? await cdp.evaluate("""
            (function(){
                // 策略1：找包含「选择封面」文字的可点击区域（往上找到卡片容器）
                var spans = document.querySelectorAll('span, div, p');
                for (var i = 0; i < spans.length; i++) {
                    if (spans[i].textContent.trim() === '选择封面') {
                        // 往上找合适大小的父容器（封面卡片通常 100-300px 宽）
                        var el = spans[i];
                        for (var j = 0; j < 8; j++) {
                            if (!el.parentElement) break;
                            el = el.parentElement;
                            var r = el.getBoundingClientRect();
                            if (r.width > 80 && r.width < 400 && r.height > 80) {
                                el.click();
                                return 'clicked_parent_' + j;
                            }
                        }
                        // 没找到合适父容器，直接点文字本身
                        spans[i].click();
                        return 'clicked_text';
                    }
                }

                // 策略2：找「设置封面」标题旁边的第一个可点击图片区域
                var allEls = document.querySelectorAll('*');
                for (var k = 0; k < allEls.length; k++) {
                    var t = allEls[k].textContent.trim();
                    if (t === '设置封面' && allEls[k].childElementCount === 0) {
                        // 找到标题后，找同级或下级的第一个大区域
                        var parent = allEls[k].parentElement;
                        if (parent) {
                            var children = parent.querySelectorAll('div, a');
                            for (var m = 0; m < children.length; m++) {
                                var cr = children[m].getBoundingClientRect();
                                if (cr.width > 80 && cr.height > 80 && cr.width < 400) {
                                    children[m].click();
                                    return 'clicked_sibling';
                                }
                            }
                        }
                    }
                }

                // 策略3：找页面中「竖封面」或「横封面」文字附近的可点击区域
                for (var n = 0; n < allEls.length; n++) {
                    var txt = allEls[n].textContent.trim();
                    if ((txt === '竖封面3:4' || txt === '横封面4:3') && allEls[n].childElementCount === 0) {
                        var p = allEls[n].parentElement;
                        if (p) {
                            p.click();
                            return 'clicked_ratio_label';
                        }
                    }
                }

                return 'not_found';
            })()
        """) as? String) ?? "error"
        log(.info, "封面点击结果: \(coverClicked)")

        if coverClicked.contains("not_found") {
            log(.warning, "所有策略都未找到封面按钮")
            return false
        }

        // 等待弹窗加载（3 秒）
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // 点击「完成」按钮（多策略）
        var completeBtnClicked = (try? await clickButtonByText(cdp: cdp, text: "完成", maxWait: 5)) ?? false

        // 如果 clickButtonByText 失败，再试 JS click
        if !completeBtnClicked {
            let jsResult = (try? await cdp.evaluate("""
                (function(){
                    var btns = document.querySelectorAll('button, [role="button"]');
                    for (var i = 0; i < btns.length; i++) {
                        var t = btns[i].textContent.trim();
                        if (t === '完成') { btns[i].click(); return 'js_clicked'; }
                    }
                    // 也试试 span/div 包裹的按钮
                    var all = document.querySelectorAll('span, div');
                    for (var j = 0; j < all.length; j++) {
                        if (all[j].textContent.trim() === '完成' && all[j].childElementCount === 0) {
                            all[j].click();
                            if (all[j].parentElement) all[j].parentElement.click();
                            return 'js_clicked_span';
                        }
                    }
                    return 'not_found';
                })()
            """) as? String) ?? "error"
            completeBtnClicked = jsResult.contains("clicked")
            log(.info, "完成按钮备用策略: \(jsResult)")
        }

        log(.info, "封面完成按钮: \(completeBtnClicked ? "成功" : "失败")")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return completeBtnClicked
    }

    // MARK: - 通用按钮点击

    /// 在页面中按文字找到 button 并点击（用坐标点击，比 JS click 更可靠）
    /// - Returns: 是否成功点击
    @discardableResult
    private func clickButtonByText(cdp: CDPClient, text: String, maxWait: Int = 3) async throws -> Bool {
        for _ in 0..<maxWait {
            let coordStr = (try? await cdp.evaluate("""
                (function(){
                    var buttons = document.querySelectorAll('button, [role="button"]');
                    for (var i = 0; i < buttons.length; i++) {
                        if (buttons[i].textContent.trim() === '\(text)') {
                            var r = buttons[i].getBoundingClientRect();
                            if (r.width > 0 && r.height > 0) {
                                return JSON.stringify({x: r.x + r.width/2, y: r.y + r.height/2});
                            }
                        }
                    }
                    return '';
                })()
            """) as? String) ?? ""

            if !coordStr.isEmpty,
               let data = coordStr.data(using: .utf8),
               let coord = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let x = coord["x"] as? Double, let y = coord["y"] as? Double {
                log(.info, "点击「\(text)」按钮: (\(Int(x)), \(Int(y)))")
                let _ = try? await cdp.send("Input.dispatchMouseEvent", params: [
                    "type": "mousePressed", "x": Int(x), "y": Int(y), "button": "left", "clickCount": 1
                ])
                let _ = try? await cdp.send("Input.dispatchMouseEvent", params: [
                    "type": "mouseReleased", "x": Int(x), "y": Int(y), "button": "left", "clickCount": 1
                ])
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    // MARK: - 定时发布

    private func setScheduleTime(cdp: CDPClient, time: Date) async {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        let timeStr = fmt.string(from: time)

        // 1. 点击"定时发布"单选按钮
        log(.info, "选择定时发布...")
        let _ = try? await cdp.evaluate("""
            (function(){
                var radios = document.querySelectorAll('.semi-radio-cardRadioGroup, .semi-radio, [class*="radio"], span, label, div');
                for (var i = 0; i < radios.length; i++) {
                    var t = radios[i].textContent.trim();
                    if (t === '定时发布') {
                        radios[i].click();
                        if (radios[i].parentElement) radios[i].parentElement.click();
                        return 'clicked';
                    }
                }
                return 'not_found';
            })()
        """)
        try? await Task.sleep(nanoseconds: stepDelay)

        // 2. 点击日期输入框，焦点 + 全选已有内容
        log(.info, "输入定时时间: \(timeStr)")
        let _ = try? await cdp.evaluate("""
            (function(){
                var input = document.querySelector('input[placeholder*="日期"], input[format*="yyyy"]');
                if (!input) return 'no_input';
                input.click();
                input.focus();
                input.select();
                return 'selected';
            })()
        """)
        try? await Task.sleep(nanoseconds: 500_000_000)

        // 3. 直接键入时间字符串（select() 全选后 insertText 会替换选中内容）
        let _ = try? await cdp.send("Input.insertText", params: ["text": timeStr])
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // 5. 按 Enter 确认
        let _ = try? await cdp.send("Input.dispatchKeyEvent", params: [
            "type": "keyDown", "key": "Enter", "code": "Enter", "windowsVirtualKeyCode": 13
        ])
        let _ = try? await cdp.send("Input.dispatchKeyEvent", params: [
            "type": "keyUp", "key": "Enter", "code": "Enter", "windowsVirtualKeyCode": 13
        ])
        try? await Task.sleep(nanoseconds: stepDelay)

        // 7. 验证是否设置成功
        let result = try? await cdp.evaluate("""
            (function(){
                var input = document.querySelector('input[placeholder*="日期"], input[format*="yyyy"]');
                return input ? input.value : 'no_input';
            })()
        """) as? String ?? ""
        log(.info, "定时发布设置结果: \(result)")
    }

    // MARK: - 点击发布

    private func clickPublishAndWait(cdp: CDPClient, aiAgent: AIAgent? = nil) async throws -> PublishResult {
        // AI 模式：让 AI 找发布按钮并点击
        if let agent = aiAgent, settings.aiMode == .full {
            do {
                try await agent.safeClick(
                    elementDescription: "找到页面右下角的红色/蓝色「发布」按钮",
                    verifyDescription: "页面开始跳转或出现发布成功提示"
                )
                // 等待发布结果（与 fallback 逻辑共享）
                let start = Date()
                while Date().timeIntervalSince(start) < 30 {
                    try await Task.sleep(nanoseconds: stepDelay)
                    let url = try await cdp.getCurrentURL()
                    if url.contains("manage") {
                        log(.success, "发布成功！（AI）")
                        return PublishResult(success: true, message: "发布成功", publishedURL: url)
                    }
                    // 处理封面弹窗
                    let _ = try? await cdp.evaluate("(function(){var b=document.querySelectorAll('button');for(var i=0;i<b.length;i++){if(b[i].textContent.trim()==='完成'){b[i].click();return'ok'}}return'no'})()")
                }
                let textAI = try await cdp.evaluate("document.body.innerText.substring(0,200)") as? String ?? ""
                if textAI.contains("发布成功") || textAI.contains("已发布") {
                    return PublishResult(success: true, message: "发布成功", publishedURL: nil)
                }
                throw DouyinPublishError.publishTimeout
            } catch let err as DouyinPublishError {
                throw err
            } catch {
                log(.warning, "AI 点击发布按钮失败，回退到旧逻辑: \(error.localizedDescription)")
            }
        }

        // Fallback：JS 按钮查找逻辑
        let _ = try await cdp.evaluate("(function(){var b=document.querySelectorAll('button');for(var i=0;i<b.length;i++){if(b[i].textContent.trim()==='发布'){b[i].click();return'ok'}}return'no'})()")

        let start = Date()
        while Date().timeIntervalSince(start) < 30 {
            try await Task.sleep(nanoseconds: stepDelay)
            let url = try await cdp.getCurrentURL()
            if url.contains("manage") {
                log(.success, "发布成功！")
                return PublishResult(success: true, message: "发布成功", publishedURL: url)
            }
            // 处理封面弹窗
            let _ = try? await cdp.evaluate("(function(){var b=document.querySelectorAll('button');for(var i=0;i<b.length;i++){if(b[i].textContent.trim()==='完成'){b[i].click();return'ok'}}return'no'})()")
        }

        let text = try await cdp.evaluate("document.body.innerText.substring(0,200)") as? String ?? ""
        if text.contains("发布成功") || text.contains("已发布") {
            return PublishResult(success: true, message: "发布成功", publishedURL: nil)
        }
        throw DouyinPublishError.publishTimeout
    }

    // MARK: - 工具

    private func sleep(_ seconds: Double = 2.0) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func log(_ level: LogLevel, _ message: String) {
        onLog?(level, message)
    }

    /// 保存诊断截图到 debug-logs/ 目录
    private func saveDebugScreenshot(cdp: CDPClient, name: String) async {
        do {
            let result = try await cdp.send("Page.captureScreenshot", params: ["format": "png"])
            guard let base64 = (result["result"] as? [String: Any])?["data"] as? String,
                  let data = Data(base64Encoded: base64) else { return }

            let fallback = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fallback
            let debugDir = appSupport.appendingPathComponent("com.menggang.douyin-uploader/debug-logs", isDirectory: true)
            try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)

            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let fileURL = debugDir.appendingPathComponent("\(name)_\(timestamp).png")
            try data.write(to: fileURL)
            log(.info, "诊断截图已保存: \(fileURL.lastPathComponent)")
        } catch {
            log(.warning, "截图保存失败: \(error.localizedDescription)")
        }
    }
}
