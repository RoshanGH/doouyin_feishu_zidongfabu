import Foundation

/// 基于 CDPClient 的 CDPDriver 具体实现
final class CDPDriverImpl: CDPDriver {

    private let client: CDPClient

    init(client: CDPClient) {
        self.client = client
    }

    // MARK: - CDPDriver

    /// 截图，返回 PNG 格式 Data
    func screenshot() async throws -> Data {
        let result = try await client.send("Page.captureScreenshot", params: ["format": "png"])
        guard
            let inner = result["result"] as? [String: Any],
            let base64 = inner["data"] as? String,
            let data = Data(base64Encoded: base64)
        else {
            throw CDPError.cdpError("截图失败：无法解析 base64 数据")
        }
        return data
    }

    /// 鼠标点击指定坐标（mousePressed + mouseReleased）
    func click(x: Int, y: Int) async throws {
        let params: [String: Any] = [
            "type": "mousePressed",
            "x": x,
            "y": y,
            "button": "left",
            "clickCount": 1
        ]
        _ = try await client.send("Input.dispatchMouseEvent", params: params)

        let releaseParams: [String: Any] = [
            "type": "mouseReleased",
            "x": x,
            "y": y,
            "button": "left",
            "clickCount": 1
        ]
        _ = try await client.send("Input.dispatchMouseEvent", params: releaseParams)
    }

    /// 向当前焦点元素插入文本
    func type(text: String) async throws {
        _ = try await client.send("Input.insertText", params: ["text": text])
    }

    /// 发送按键事件（keyDown + keyUp）
    func pressKey(_ key: String) async throws {
        let downParams: [String: Any] = ["type": "keyDown", "key": key]
        _ = try await client.send("Input.dispatchKeyEvent", params: downParams)

        let upParams: [String: Any] = ["type": "keyUp", "key": key]
        _ = try await client.send("Input.dispatchKeyEvent", params: upParams)
    }

    /// 通过 CSS 选择器找到 file input 并设置文件路径
    func uploadFiles(selector: String, paths: [String]) async throws {
        try await client.setFileInputFiles(selector: selector, files: paths)
    }

    /// 鼠标滚轮滚动
    func scroll(deltaX: Int, deltaY: Int) async throws {
        let params: [String: Any] = [
            "type": "mouseWheel",
            "x": 0,
            "y": 0,
            "deltaX": deltaX,
            "deltaY": deltaY
        ]
        _ = try await client.send("Input.dispatchMouseEvent", params: params)
    }

    /// 导航到指定 URL，等待页面加载完成
    func navigate(to url: String) async throws {
        try await client.navigate(to: url)
    }

    /// 获取当前页面 URL
    func getCurrentURL() async throws -> String {
        try await client.getCurrentURL()
    }

    /// 执行 JavaScript 表达式并返回结果
    func evaluate(_ js: String) async throws -> Any? {
        try await client.evaluate(js)
    }
}
