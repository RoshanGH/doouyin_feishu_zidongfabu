import SwiftUI
import WebKit

/// 扫码登录弹窗 — 显示抖音登录 Web 页面
/// 自动滚动到二维码位置，用户扫码后自动检测登录成功
struct QRCodeLoginView: View {

    @ObservedObject var viewModel: AccountViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("扫码登录抖音")
                    .font(.headline)
                Spacer()
                Button("取消") {
                    viewModel.cancelLogin()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            DouyinLoginWebView(
                onLoginSuccess: { cookies, nickname, douyinId, avatar in
                    viewModel.handleWebViewLoginSuccess(
                        cookies: cookies,
                        nickname: nickname,
                        douyinId: douyinId,
                        avatarUrl: avatar
                    )
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 460, height: 620)
    }
}

// MARK: - WKWebView 包装

struct DouyinLoginWebView: NSViewRepresentable {

    let onLoginSuccess: ([HTTPCookie], String, String, String?) -> Void

    func makeNSView(context: Context) -> FocusableWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = FocusableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        if let url = URL(string: "https://creator.douyin.com/") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ nsView: FocusableWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: DouyinLoginWebView
        private var hasDetectedLogin = false
        private var pollTimer: Timer?
        private var hasScrolledToQR = false

        init(parent: DouyinLoginWebView) {
            self.parent = parent
        }

        deinit {
            pollTimer?.invalidate()
        }

        // 拦截自定义协议（如 bitbrowser://）
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let scheme = navigationAction.request.url?.scheme?.lowercased(),
               scheme != "http" && scheme != "https" && scheme != "about" && scheme != "data" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 页面加载完成后：滚动到二维码位置 + 启动登录轮询
            if !hasScrolledToQR {
                scrollToQRCode(webView: webView)
            }
            startPolling(webView: webView)
        }

        // MARK: - 滚动到二维码位置

        private func scrollToQRCode(webView: WKWebView) {
            // 延迟等待页面渲染完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                let js = #"""
                (function() {
                    // 找到二维码图片
                    var qr = document.querySelector('img[aria-label="二维码"]');
                    if (!qr) {
                        var imgs = document.querySelectorAll('img');
                        for (var i = 0; i < imgs.length; i++) {
                            if (imgs[i].src && imgs[i].src.startsWith('data:image') && imgs[i].width > 100 && imgs[i].width < 400) {
                                qr = imgs[i];
                                break;
                            }
                        }
                    }
                    if (qr) {
                        qr.scrollIntoView({ behavior: 'smooth', block: 'center' });
                        return true;
                    }
                    // 找到"扫码登录"标签并滚动
                    var tabs = document.querySelectorAll('span, div');
                    for (var i = 0; i < tabs.length; i++) {
                        if (tabs[i].textContent.trim() === '扫码登录') {
                            tabs[i].scrollIntoView({ behavior: 'smooth', block: 'start' });
                            return true;
                        }
                    }
                    return false;
                })()
                """#
                webView.evaluateJavaScript(js) { [weak self] _, _ in
                    self?.hasScrolledToQR = true
                }
            }
        }

        // MARK: - 轮询登录检测

        private func startPolling(webView: WKWebView) {
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.checkLogin(webView: webView)
                }
            }
        }

        private func checkLogin(webView: WKWebView) {
            guard !hasDetectedLogin else {
                pollTimer?.invalidate()
                return
            }

            let checkJS = #"""
            (function() {
                var text = document.body ? document.body.innerText : '';
                var url = window.location.href;
                return JSON.stringify({
                    url: url,
                    isCreatorPage: url.indexOf('creator-micro') !== -1,
                    hasScanLogin: text.indexOf('扫码登录') !== -1,
                    hasPhoneLogin: text.indexOf('手机号登录') !== -1
                });
            })()
            """#

            webView.evaluateJavaScript(checkJS) { [weak self] result, _ in
                guard let self, !self.hasDetectedLogin else { return }
                guard let jsonStr = result as? String,
                      let data = jsonStr.data(using: .utf8),
                      let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                let isCreatorPage = info["isCreatorPage"] as? Bool ?? false
                let hasScanLogin = info["hasScanLogin"] as? Bool ?? false
                let hasPhoneLogin = info["hasPhoneLogin"] as? Bool ?? false
                let url = info["url"] as? String ?? ""

                // 登录成功：进入了后台页面，或者登录页标记消失了
                let loginPageGone = !hasScanLogin && !hasPhoneLogin
                    && !url.contains("passport") && !url.contains("login")
                let isLoggedIn = isCreatorPage || loginPageGone

                if isLoggedIn {
                    self.hasDetectedLogin = true
                    self.pollTimer?.invalidate()

                    // 等 Cookie 写入完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.extractAndComplete(webView: webView)
                    }
                }
            }
        }

        // MARK: - 提取信息 + 完成

        private func extractAndComplete(webView: WKWebView) {
            // 先导航到首页，首页有完整的用户信息（昵称、抖音号、头像）
            let homeURL = URL(string: "https://creator.douyin.com/creator-micro/home")!
            webView.load(URLRequest(url: homeURL))

            // 等首页加载完成后提取信息
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                self?.doExtract(webView: webView)
            }
        }

        private func doExtract(webView: WKWebView) {
            let js = #"""
            (function() {
                var result = { nickname: '', douyinId: '', avatar: '' };
                var allText = document.body.innerText || '';

                // 1. 提取抖音号：匹配 "抖音号：xxx"
                var idMatch = allText.match(/抖音号[：:]\s*([a-zA-Z0-9_]+)/);
                if (idMatch) result.douyinId = idMatch[1];

                // 2. 提取昵称：侧边栏中 class 含 "name-" 且只有一个短文本的 div
                //    排除 "高清发布"、"抖音官网" 等非用户名元素
                var nameEls = document.querySelectorAll('div[class*="name-"], span[class*="name-"]');
                var blacklist = ['高清发布', '抖音官网', '巨量星图', '企业号', '直播', '开放平台', '登录', '注册'];
                for (var i = 0; i < nameEls.length; i++) {
                    var t = nameEls[i].textContent.trim();
                    if (t && t.length >= 1 && t.length <= 20) {
                        var skip = false;
                        for (var j = 0; j < blacklist.length; j++) {
                            if (t.indexOf(blacklist[j]) !== -1) { skip = true; break; }
                        }
                        if (!skip) {
                            result.nickname = t;
                            break;
                        }
                    }
                }

                // 3. 提取头像：找 class 含 "avatar-" 的 div 的 background-image
                var avatarDivs = document.querySelectorAll('div[class*="avatar-"]');
                for (var i = 0; i < avatarDivs.length; i++) {
                    var bg = avatarDivs[i].style.backgroundImage || '';
                    var urlMatch = bg.match(/url\(["']?(https?:\/\/[^"')]+)/);
                    if (urlMatch) {
                        result.avatar = urlMatch[1];
                        break;
                    }
                }
                // 备选：img 标签
                if (!result.avatar) {
                    var avatarImg = document.querySelector('img[src*="aweme-avatar"], img[src*="avatar"]');
                    if (avatarImg && avatarImg.src) result.avatar = avatarImg.src;
                }

                return JSON.stringify(result);
            })()
            """#

            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self else { return }
                var nickname = ""
                var douyinId = ""
                var avatar: String? = nil

                if let jsonStr = result as? String,
                   let data = jsonStr.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    nickname = dict["nickname"] ?? ""
                    douyinId = dict["douyinId"] ?? ""
                    let av = dict["avatar"] ?? ""
                    if !av.isEmpty { avatar = av }
                }

                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    let douyinCookies = cookies.filter { $0.domain.contains("douyin.com") }
                    guard !douyinCookies.isEmpty else { return }
                    DispatchQueue.main.async {
                        self.parent.onLoginSuccess(douyinCookies, nickname, douyinId, avatar)
                    }
                }
            }
        }
    }
}

// MARK: - 可接收键盘输入的 WKWebView

/// 默认 WKWebView 在 NSViewRepresentable 中无法成为 first responder，
/// 导致输入框无法输入。重写 acceptsFirstResponder 解决。
final class FocusableWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        return super.becomeFirstResponder()
    }

    // 点击时自动获取焦点
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }
}
