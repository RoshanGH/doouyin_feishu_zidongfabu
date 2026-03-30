import Foundation

/// Chrome DevTools Protocol 客户端
/// 通过 WebSocket 与 Chrome 实例通信
final class CDPClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var messageId = 0
    private let lock = NSLock()
    private var pendingCallbacks: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var eventHandlers: [String: ([String: Any]) -> Void] = [:]
    private var isConnected = false

    // MARK: - 连接

    func connect(wsURL: String) async throws {
        guard let url = URL(string: wsURL) else {
            throw CDPError.invalidURL(wsURL)
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        let ws = session!.webSocketTask(with: url)
        ws.maximumMessageSize = 10 * 1024 * 1024 // 10MB（默认 1MB，CDP 响应可能很大）
        ws.resume()
        self.webSocket = ws
        self.isConnected = true

        // 必须先启动接收循环，再发送任何命令
        startReceiveLoop()

        // 等待 WebSocket 连接稳定（didOpen 回调触发）
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // 启用必要的域
        _ = try await send("Page.enable")
        _ = try await send("DOM.enable")
        _ = try await send("Network.enable")
        _ = try await send("Runtime.enable")
    }

    func disconnect() {
        isConnected = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil

        lock.lock()
        for (_, continuation) in pendingCallbacks {
            continuation.resume(throwing: CDPError.disconnected)
        }
        pendingCallbacks.removeAll()
        lock.unlock()
    }

    // MARK: - 发送命令

    @discardableResult
    func send(_ method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        guard let ws = webSocket, isConnected else { throw CDPError.notConnected }

        lock.lock()
        messageId += 1
        let id = messageId
        lock.unlock()

        var command: [String: Any] = ["id": id, "method": method]
        if let params { command["params"] = params }

        let data = try JSONSerialization.data(withJSONObject: command)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw CDPError.cdpError("JSON 编码失败")
        }
        try await ws.send(.string(jsonString))

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pendingCallbacks[id] = continuation
            lock.unlock()
        }
    }

    /// 注册事件处理器
    func onEvent(_ name: String, handler: @escaping ([String: Any]) -> Void) {
        lock.lock()
        eventHandlers[name] = handler
        lock.unlock()
    }

    // MARK: - 高级操作

    func navigate(to url: String) async throws {
        _ = try await send("Page.navigate", params: ["url": url])
        // 等待页面加载（简单等待，不依赖事件）
        try await Task.sleep(nanoseconds: 3_000_000_000)
    }

    func setCookie(name: String, value: String, domain: String, path: String = "/") async throws {
        _ = try await send("Network.setCookie", params: [
            "name": name, "value": value, "domain": domain, "path": path
        ])
    }

    func setCookies(_ cookies: [(name: String, value: String, domain: String, path: String)]) async throws {
        let list = cookies.map { c -> [String: Any] in
            ["name": c.name, "value": c.value, "domain": c.domain, "path": c.path]
        }
        _ = try await send("Network.setCookies", params: ["cookies": list])
    }

    func evaluate(_ expression: String) async throws -> Any? {
        let result = try await send("Runtime.evaluate", params: [
            "expression": expression,
            "returnByValue": true,
            "awaitPromise": true
        ])
        if let r = result["result"] as? [String: Any],
           let inner = r["result"] as? [String: Any] {
            return inner["value"]
        }
        return nil
    }

    func waitForSelector(_ selector: String, timeout: TimeInterval = 30) async throws -> Int {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let docResult = try await send("DOM.getDocument")
            if let root = (docResult["result"] as? [String: Any])?["root"] as? [String: Any],
               let rootId = root["nodeId"] as? Int {
                let qResult = try await send("DOM.querySelector", params: [
                    "nodeId": rootId, "selector": selector
                ])
                if let nodeId = (qResult["result"] as? [String: Any])?["nodeId"] as? Int, nodeId > 0 {
                    return nodeId
                }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw CDPError.timeout("等待元素超时: \(selector)")
    }

    func setFileInputFiles(selector: String, files: [String]) async throws {
        let nodeId = try await waitForSelector(selector, timeout: 10)
        _ = try await send("DOM.setFileInputFiles", params: [
            "nodeId": nodeId, "files": files
        ])
    }

    func getCurrentURL() async throws -> String {
        return try await evaluate("window.location.href") as? String ?? ""
    }

    /// 获取指定域名的所有 Cookie
    func getCookies(domain: String) async throws -> [[String: Any]] {
        let result = try await send("Network.getCookies", params: ["urls": ["https://\(domain)"]])
        if let cookies = (result["result"] as? [String: Any])?["cookies"] as? [[String: Any]] {
            return cookies
        }
        return []
    }

    func waitForURL(containing text: String, timeout: TimeInterval = 60) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let url = try await getCurrentURL()
            if url.contains(text) { return }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw CDPError.timeout("等待 URL 包含 '\(text)' 超时")
    }

    // MARK: - 接收循环（独立线程）

    private func startReceiveLoop() {
        receiveNext()
    }

    private func receiveNext() {
        guard let ws = webSocket, isConnected else { return }
        ws.receive { [weak self] result in
            guard let self, self.isConnected else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) { self.handleMessage(data) }
                case .data(let data):
                    self.handleMessage(data)
                @unknown default:
                    break
                }
                self.receiveNext() // 继续接收下一条
            case .failure(let error):
                print("[CDP] WebSocket receive error: \(error.localizedDescription)")
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // 响应（有 id）
        if let id = json["id"] as? Int {
            lock.lock()
            let continuation = pendingCallbacks.removeValue(forKey: id)
            lock.unlock()

            if let continuation {
                if let error = json["error"] as? [String: Any] {
                    let msg = error["message"] as? String ?? "CDP 错误"
                    continuation.resume(throwing: CDPError.cdpError(msg))
                } else {
                    continuation.resume(returning: json)
                }
            }
            return
        }

        // 事件（有 method）
        if let method = json["method"] as? String {
            let params = json["params"] as? [String: Any] ?? [:]
            eventHandlers[method]?(params)
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[CDP] WebSocket 已连接")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[CDP] WebSocket 已关闭: \(closeCode)")
        isConnected = false
    }
}

// MARK: - 错误

enum CDPError: LocalizedError {
    case notConnected
    case disconnected
    case invalidURL(String)
    case timeout(String)
    case jsError(String)
    case cdpError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "未连接到 Chrome"
        case .disconnected: return "Chrome 连接已断开"
        case .invalidURL(let url): return "无效的 WebSocket URL: \(url)"
        case .timeout(let msg): return msg
        case .jsError(let msg): return "JS 执行错误: \(msg)"
        case .cdpError(let msg): return "CDP 协议错误: \(msg)"
        }
    }
}
