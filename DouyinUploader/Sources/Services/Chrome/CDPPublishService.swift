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
                    result = try await publishVideo(cdp: cdp, task: task, localFiles: localFiles)
                } else if task.isImagePost {
                    result = try await publishImages(cdp: cdp, task: task, localFiles: localFiles)
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

    /// 检测页面是否弹出验证码（滑块/拼图/图片验证等）
    /// 检测范围：页面主体 + dialog 弹窗 + iframe
    /// 触发后：暂停队列，三重提醒用户，无限等待直到验证通过
    private func checkVerification(cdp: CDPClient) async throws {
        let hasV = (try? await cdp.evaluate("""
            (function() {
                // 主页面文本
                var t = document.body ? document.body.innerText : '';
                // dialog / 弹窗
                var dialogs = document.querySelectorAll('[role="dialog"], .semi-modal, [class*="modal"], [class*="captcha"], [class*="verify"]');
                for (var i = 0; i < dialogs.length; i++) { t += ' ' + dialogs[i].innerText; }
                // iframe（同域才能读取）
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

        guard hasV else { return }

        log(.warning, "⚠️ 检测到验证码！任务已暂停，请在 Chrome 窗口中手动完成验证")

        // 三重提醒
        await notifyUserForVerification()

        // 无限等待，直到验证码消失
        var seconds = 0
        while true {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            seconds += 2

            let still = (try? await cdp.evaluate("""
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

            if !still {
                log(.info, "✅ 验证码已通过（等待了 \(seconds)s）")
                // 验证通过后等一下让页面恢复
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return
            }

            if seconds % 30 == 0 {
                log(.info, "⏳ 仍在等待验证码处理...（已等待 \(seconds)s）")
                // 每 30 秒重新提醒一次
                await notifyUserForVerification()
            }
        }
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

    private func publishVideo(cdp: CDPClient, task: PublishTask, localFiles: [URL]) async throws -> PublishResult {
        guard let videoFile = localFiles.first else { throw DouyinPublishError.localFilesNotProvided }

        // 1. 加载上传页
        log(.info, "加载抖音上传页...")
        try await cdp.navigate(to: "https://creator.douyin.com/creator-micro/content/upload")
        try await sleep()

        // 检测登录是否过期（Cookie 失效会跳转到登录页）
        try await checkLoginStatus(cdp: cdp, accountId: task.douyinAccountId)
        try await checkVerification(cdp: cdp)

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
        try await checkVerification(cdp: cdp)

        // 4. 等待跳转到发布信息页
        log(.info, "等待视频处理...")
        try await cdp.waitForURL(containing: "publish", timeout: 180)
        log(.info, "已进入发布信息页")
        try await sleep(2)
        try await checkVerification(cdp: cdp)

        // 5. 填写标题
        let titleText = (task.title ?? task.content).prefix(30).description
        await fillTitle(cdp: cdp, title: titleText)
        try await sleep()
        try await checkVerification(cdp: cdp)

        // 6. 填写文案和话题
        await fillDescription(cdp: cdp, content: task.content, tags: task.tags)
        try await sleep()
        try await checkVerification(cdp: cdp)

        // 7. 设置封面
        await setCover(cdp: cdp)
        try await sleep()
        try await checkVerification(cdp: cdp)

        // 8. 定时发布
        if let time = task.scheduledTime {
            log(.info, "设置定时发布...")
            await setScheduleTime(cdp: cdp, time: time)
            try await sleep()
            try await checkVerification(cdp: cdp)
        }

        // 9. 点击发布
        log(.info, "点击发布...")
        return try await clickPublishAndWait(cdp: cdp)
    }

    // MARK: - 图文发布

    private func publishImages(cdp: CDPClient, task: PublishTask, localFiles: [URL]) async throws -> PublishResult {
        log(.info, "加载抖音上传页...")
        try await cdp.navigate(to: "https://creator.douyin.com/creator-micro/content/upload")
        try await sleep()

        // 检测登录是否过期
        try await checkLoginStatus(cdp: cdp, accountId: task.douyinAccountId)
        try await checkVerification(cdp: cdp)

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
        try await checkVerification(cdp: cdp)

        // 上传图片
        log(.info, "上传 \(localFiles.count) 张图片...")
        try await cdp.setFileInputFiles(
            selector: "div[class^='container'] input[accept*='image'], div[class^='container'] input, input[type='file']",
            files: localFiles.map { $0.path }
        )
        try await sleep()
        try await checkVerification(cdp: cdp)

        try await cdp.waitForURL(containing: "publish", timeout: 120)
        log(.info, "已进入发布信息页")
        try await sleep(2)
        try await checkVerification(cdp: cdp)

        // 标题
        if let title = task.title, !title.isEmpty {
            await fillTitle(cdp: cdp, title: String(title.prefix(30)))
            try await sleep()
            try await checkVerification(cdp: cdp)
        }

        // 文案 + 话题
        await fillDescription(cdp: cdp, content: task.content, tags: task.tags)
        try await sleep()
        try await checkVerification(cdp: cdp)

        // 定时
        if let time = task.scheduledTime {
            log(.info, "设置定时发布...")
            await setScheduleTime(cdp: cdp, time: time)
            try await sleep()
            try await checkVerification(cdp: cdp)
        }

        log(.info, "点击发布...")
        return try await clickPublishAndWait(cdp: cdp)
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

    /// 点击「选择封面」或「设置封面」→ 等弹窗加载 → 点击「完成」
    private func setCover(cdp: CDPClient) async {
        log(.info, "设置封面...")

        // 1. 找到「选择封面」的坐标，用 CDP 鼠标点击（比 JS click 更可靠）
        let coordStr = (try? await cdp.evaluate("""
            (function(){
                var all = document.querySelectorAll('*');
                var best = null;
                for (var i = 0; i < all.length; i++) {
                    var t = all[i].textContent.trim();
                    if (t === '选择封面') {
                        var r = all[i].getBoundingClientRect();
                        if (r.width > 0 && r.height > 0 && r.width < 200) {
                            if (!best || r.width < best.w) {
                                best = {x: r.x + r.width/2, y: r.y + r.height/2, w: r.width};
                            }
                        }
                    }
                }
                return best ? JSON.stringify({x: best.x, y: best.y}) : '';
            })()
        """) as? String) ?? ""

        if coordStr.isEmpty {
            log(.warning, "未找到封面按钮，跳过")
            return
        }

        // 解析坐标并模拟鼠标点击
        if let data = coordStr.data(using: .utf8),
           let coord = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let x = coord["x"] as? Double, let y = coord["y"] as? Double {
            log(.info, "点击「选择封面」坐标: (\(Int(x)), \(Int(y)))")
            let _ = try? await cdp.send("Input.dispatchMouseEvent", params: [
                "type": "mousePressed", "x": Int(x), "y": Int(y), "button": "left", "clickCount": 1
            ])
            let _ = try? await cdp.send("Input.dispatchMouseEvent", params: [
                "type": "mouseReleased", "x": Int(x), "y": Int(y), "button": "left", "clickCount": 1
            ])
        } else {
            log(.warning, "封面按钮坐标解析失败，跳过")
            return
        }

        // 2. 等待 2 秒让弹窗加载
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // 3. 在弹窗中点击「完成」按钮
        let coverResult = (try? await cdp.evaluate("""
            (function(){
                var buttons = document.querySelectorAll('button');
                for (var i = 0; i < buttons.length; i++) {
                    if (buttons[i].textContent.trim() === '完成') {
                        buttons[i].click();
                        return 'clicked';
                    }
                }
                return 'not_found';
            })()
        """) as? String) ?? "error"
        log(.info, "封面完成按钮: \(coverResult)")

        // 4. 等待 1 秒让弹窗关闭
        try? await Task.sleep(nanoseconds: 1_000_000_000)
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

    private func clickPublishAndWait(cdp: CDPClient) async throws -> PublishResult {
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
}
