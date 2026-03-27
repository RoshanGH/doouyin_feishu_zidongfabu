import XCTest
import WebKit
@testable import DouyinUploader

/// Spike S1 + S2: WKWebView off-screen 执行 + 文件上传验证
/// ⚠️ 这些测试需要在有窗口环境的 macOS App 中运行（非 CLI `swift test`）
/// 运行方式：在 Xcode 中右键 Run 单个测试，或在调试模式 App 中手动触发
final class WebViewSpikeTests: XCTestCase {

    /// S1: 验证 off-screen WKWebView 中 JS 能正常执行
    func test_S1_offScreenJSExecution() async throws {
        // 跳过 CLI 环境（无窗口系统）
        try XCTSkipIf(ProcessInfo.processInfo.environment["RUNNING_IN_XCODE"] == nil,
                      "Spike Test 需要在 Xcode / App 环境中运行")

        let expectation = XCTestExpectation(description: "JS 执行完成")

        await MainActor.run {
            // 创建 off-screen 窗口
            let window = NSWindow(
                contentRect: CGRect(x: -10000, y: -10000, width: 1280, height: 800),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: window.contentRect(forFrameRect: window.frame), configuration: config)
            window.contentView?.addSubview(webView)

            // 加载简单 HTML
            let html = "<html><head><title>SpikeTest</title></head><body>Hello</body></html>"
            webView.loadHTMLString(html, baseURL: nil)

            // 延迟后执行 JS
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                webView.evaluateJavaScript("1 + 1") { result, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(result as? Int, 2)
                    expectation.fulfill()
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 5)
    }

    /// S2: 验证文件上传 runOpenPanel 是否被触发
    /// 这是最高风险验证点
    func test_S2_fileUploadTrigger() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["RUNNING_IN_XCODE"] == nil,
                      "Spike Test 需要在 Xcode / App 环境中运行")

        // TODO: 在 Xcode 环境中实现完整验证
        // 1. 创建含 <input type="file"> 的页面
        // 2. 实现 WKUIDelegate.webView(_:runOpenPanelWith:)
        // 3. 通过 JS evaluateJavaScript("input.click()") 触发
        // 4. 验证 runOpenPanel 被调用
        //
        // 如果方案 A 失败，按顺序尝试：
        // - 方案 B: 在 onclick 事件中触发 input.click()
        // - 方案 C: 构造 DragEvent + DataTransfer
        // - 方案 D: 拦截 FormData.append()
        // - 方案 E: 可见但最小化的窗口

        XCTFail("请在 Xcode 中手动运行此测试，验证文件上传方案")
    }
}
