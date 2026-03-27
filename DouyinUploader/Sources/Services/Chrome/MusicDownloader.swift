import Foundation

/// 从抖音创作者中心下载音乐文件
/// 流程：打开文章页 → 选择音乐 → 搜索 → 拦截网络请求获取音频URL → 下载
final class MusicDownloader {

    private let stepDelay: UInt64 = 2_000_000_000

    var onLog: ((LogLevel, String) -> Void)?

    /// 搜索并下载音乐
    /// - Parameters:
    ///   - cdp: 已连接的 CDP 客户端
    ///   - musicName: 搜索关键字
    /// - Returns: 下载到本地的音乐文件 URL，失败返回 nil
    func downloadMusic(cdp: CDPClient, musicName: String) async -> URL? {
        log(.info, "开始获取音乐: \(musicName)")

        // 1. 打开文章发布页（有"选择音乐"按钮）
        log(.info, "加载文章发布页...")
        do {
            try await cdp.navigate(to: "https://creator.douyin.com/creator-micro/content/post/article?default-tab=5&enter_from=publish_page&media_type=article&type=new")
        } catch {
            log(.error, "加载文章页失败: \(error.localizedDescription)")
            return nil
        }
        try? await Task.sleep(nanoseconds: stepDelay * 2)

        // 2. 启用网络拦截（捕获音频文件URL）
        // 实际音频URL在 douyinstatic.com/obj/tos-cn-ve- 域名下，没有文件后缀
        var capturedAudioURL: String?
        do {
            try await cdp.send("Network.enable")
            cdp.onEvent("Network.responseReceived") { params in
                if let response = params["response"] as? [String: Any],
                   let url = response["url"] as? String {
                    let mimeType = response["mimeType"] as? String ?? ""
                    // 匹配抖音 CDN 音频文件（域名含 douyinstatic/tos，或 MIME 含 audio）
                    let isAudioCDN = url.contains("douyinstatic.com/obj/tos-cn-ve")
                        || url.contains("douyinstatic.com/obj/tos-cn-p")
                        || url.contains("bytecdn.cn") && url.contains("tos-cn")
                    let isAudioMime = mimeType.contains("audio") || mimeType.contains("octet-stream")

                    if isAudioCDN || (isAudioMime && !url.contains("search") && !url.contains("api")) {
                        capturedAudioURL = url
                    }
                }
            }
        } catch {
            log(.warning, "网络拦截设置失败")
        }

        // 3. 点击"选择音乐"（class="action-Q1y01k" 或文字匹配）
        log(.info, "点击「选择音乐」...")
        let clickResult = try? await cdp.evaluate("""
            (function(){
                // 方式1：直接用 class 选择器（从 DOM 截图确认）
                var btn = document.querySelector('[class*="action-Q1y01k"], [class*="action-"]');
                if (btn && btn.textContent.indexOf('选择音乐') !== -1) {
                    btn.click();
                    return 'clicked_class';
                }
                // 方式2：找"选择音乐"文字，点击它和父元素
                var els = document.querySelectorAll('span, div, button, a');
                for (var i = 0; i < els.length; i++) {
                    var t = els[i].textContent.trim();
                    if (t === '选择音乐' || t === '选择配乐') {
                        els[i].click();
                        if (els[i].parentElement) els[i].parentElement.click();
                        return 'clicked_text: ' + els[i].className;
                    }
                }
                return 'not_found';
            })()
        """) as? String ?? "error"
        log(.info, "选择音乐点击结果: \(clickResult)")
        try? await Task.sleep(nanoseconds: stepDelay * 2)

        // 4. 等待搜索框出现
        var searchFound = false
        for _ in 0..<5 {
            let r = try? await cdp.evaluate("(function(){return document.querySelector('input[placeholder=\"搜索音乐\"]')?'yes':'no'})()") as? String
            if r == "yes" { searchFound = true; break }
            try? await Task.sleep(nanoseconds: stepDelay)
        }
        if !searchFound {
            log(.warning, "音乐面板未打开")
            return nil
        }

        // 5. 搜索音乐
        log(.info, "搜索: \(musicName)")
        let _ = try? await cdp.evaluate("""
            (function(){
                var input = document.querySelector('input[placeholder="搜索音乐"]');
                if (!input) return 'no';
                input.click(); input.focus();
                var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
                setter.call(input, '');
                input.dispatchEvent(new Event('input', {bubbles: true}));
                return 'ok';
            })()
        """)
        try? await Task.sleep(nanoseconds: stepDelay)

        let _ = try? await cdp.send("Input.insertText", params: ["text": musicName])
        try? await Task.sleep(nanoseconds: stepDelay)

        let _ = try? await cdp.send("Input.dispatchKeyEvent", params: ["type": "keyDown", "key": "Enter", "code": "Enter", "windowsVirtualKeyCode": 13])
        let _ = try? await cdp.send("Input.dispatchKeyEvent", params: ["type": "keyUp", "key": "Enter", "code": "Enter", "windowsVirtualKeyCode": 13])
        try? await Task.sleep(nanoseconds: stepDelay * 2)

        // 6. 点击第一个结果的预览/播放（触发音频加载）
        log(.info, "播放第一个搜索结果...")
        let _ = try? await cdp.evaluate("""
            (function(){
                // 点击第一个音乐卡片（触发预览播放，加载音频文件）
                var card = document.querySelector('[class*="card-container-"]');
                if (card) { card.click(); return 'clicked_card'; }
                // 备选：点击封面图
                var cover = document.querySelector('[class*="music-cover-"]');
                if (cover) { cover.click(); return 'clicked_cover'; }
                return 'no_card';
            })()
        """)
        try? await Task.sleep(nanoseconds: stepDelay * 2)

        // 7. 同时从页面中提取音频 URL（备选方案）
        if capturedAudioURL == nil {
            let urlFromPage = try? await cdp.evaluate("""
                (function(){
                    // 方式1：查找 audio 标签
                    var audio = document.querySelector('audio');
                    if (audio && audio.src) return audio.src;

                    // 方式2：查找 video 标签（有些音乐用 video 播放）
                    var video = document.querySelector('video[src*="music"], video[src*="audio"]');
                    if (video && video.src) return video.src;

                    // 方式3：从 React 内部状态提取
                    // Semi Design 的音乐播放器可能在 window.__NEXT_DATA__ 或其他全局变量中

                    return '';
                })()
            """) as? String

            if let url = urlFromPage, !url.isEmpty {
                capturedAudioURL = url
            }
        }

        // 8. 如果还没捕获到，尝试强制点击"使用"按钮触发更多网络请求
        if capturedAudioURL == nil {
            log(.info, "尝试点击使用按钮获取音频URL...")
            let _ = try? await cdp.evaluate("""
                (function(){
                    var card = document.querySelector('[class*="card-container-"]');
                    if (card) {
                        card.dispatchEvent(new MouseEvent('mouseenter', {bubbles: true}));
                        var btn = card.querySelector('button[class*="apply-btn-"]');
                        if (btn) { btn.style.display = 'block'; btn.click(); return 'clicked'; }
                    }
                    var allBtns = document.querySelectorAll('button[class*="apply-btn-"]');
                    if (allBtns.length > 0) { allBtns[0].style.display = 'block'; allBtns[0].click(); return 'force_clicked'; }
                    return 'no_btn';
                })()
            """)
            try? await Task.sleep(nanoseconds: stepDelay * 2)
        }

        // 9. 最后一次尝试从网络请求中获取
        if capturedAudioURL == nil {
            // 从 Performance API 获取所有网络请求
            let urls = try? await cdp.evaluate("""
                (function(){
                    var entries = performance.getEntriesByType('resource');
                    var audioUrls = [];
                    for (var i = 0; i < entries.length; i++) {
                        var url = entries[i].name;
                        if (url.indexOf('.mp3') !== -1 || url.indexOf('.m4a') !== -1 || url.indexOf('music') !== -1 || url.indexOf('audio') !== -1) {
                            audioUrls.push(url);
                        }
                    }
                    return JSON.stringify(audioUrls);
                })()
            """) as? String

            if let urls, let data = urls.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
               let firstURL = arr.first {
                capturedAudioURL = firstURL
            }
        }

        guard let audioURL = capturedAudioURL, !audioURL.isEmpty else {
            log(.warning, "无法获取音乐播放URL")
            return nil
        }

        log(.info, "获取到音频URL: \(audioURL.prefix(80))...")

        // 10. 通过浏览器下载音频（带 cookie/referer 避免 403）
        return await downloadAudioViaCDP(cdp: cdp, urlString: audioURL, musicName: musicName)
    }

    // MARK: - 下载音频文件

    /// 通过 CDP 在浏览器内下载音频（带 cookie/referer，避免 403）
    private func downloadAudioViaCDP(cdp: CDPClient, urlString: String, musicName: String) async -> URL? {
        log(.info, "通过浏览器下载音频...")

        // 在浏览器中用 fetch 下载音频，转为 base64
        let escaped = urlString.replacingOccurrences(of: "'", with: "\\'")
        let result = try? await cdp.evaluate("""
            (async function(){
                try {
                    var resp = await fetch('\(escaped)');
                    if (!resp.ok) return JSON.stringify({error: 'HTTP ' + resp.status});
                    var blob = await resp.blob();
                    return new Promise(function(resolve){
                        var reader = new FileReader();
                        reader.onloadend = function(){
                            resolve(JSON.stringify({
                                data: reader.result.split(',')[1],
                                size: blob.size,
                                type: blob.type
                            }));
                        };
                        reader.readAsDataURL(blob);
                    });
                } catch(e) {
                    return JSON.stringify({error: e.message});
                }
            })()
        """) as? String

        guard let result, let jsonData = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            log(.error, "浏览器下载失败：无响应")
            return nil
        }

        if let error = json["error"] as? String {
            log(.error, "浏览器下载失败: \(error)")
            return nil
        }

        guard let base64 = json["data"] as? String,
              let audioData = Data(base64Encoded: base64), audioData.count > 1000 else {
            log(.error, "音频数据无效")
            return nil
        }

        // 保存到本地
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("douyin_music", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let safeName = String(musicName.replacingOccurrences(of: "/", with: "_").prefix(30))
        let mimeType = json["type"] as? String ?? ""
        let ext = mimeType.contains("m4a") ? "m4a" : "mp3"
        let localURL = tempDir.appendingPathComponent("\(safeName).\(ext)")
        try? FileManager.default.removeItem(at: localURL)

        do {
            try audioData.write(to: localURL)
            log(.info, "音乐下载完成: \(localURL.lastPathComponent) (\(audioData.count / 1024)KB)")
            return localURL
        } catch {
            log(.error, "音乐写入失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func log(_ level: LogLevel, _ message: String) {
        onLog?(level, message)
    }
}
