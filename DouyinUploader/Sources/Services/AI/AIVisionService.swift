import Foundation
import AppKit

/// AI Vision API 调用服务
/// 发送截图给 OpenAI 兼容 API，获取操作指令
final class AIVisionService {

    private let config: AIConfig
    private let session: URLSession

    /// 断路器状态
    private var consecutiveFailures = 0
    private var circuitOpenUntil: Date?
    private let maxConsecutiveFailures = 3
    private let circuitOpenDuration: TimeInterval = 60

    init(config: AIConfig) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: sessionConfig)
    }

    /// 发送截图给 AI 分析
    /// - Parameters:
    ///   - screenshot: PNG 截图数据
    ///   - prompt: 分析指令
    /// - Returns: AI 分析结果
    func analyze(screenshot: Data, prompt: String) async throws -> AIAnalysisResult {
        // 断路器检查
        if let openUntil = circuitOpenUntil, Date() < openUntil {
            throw AIServiceError.circuitOpen
        }

        // 压缩截图
        let compressed = compressScreenshot(screenshot)
        let base64Image = compressed.base64EncodedString()

        // 构建请求体（OpenAI 兼容格式）
        let requestBody: [String: Any] = [
            "model": config.model,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        guard let url = URL(string: "\(config.baseURL)/chat/completions") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            recordFailure()
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            recordFailure()
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.httpError(httpResponse.statusCode, body)
        }

        // 解析 OpenAI 格式的响应
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            recordFailure()
            throw AIServiceError.parseError("无法解析 API 响应")
        }

        // 从 content 中提取 JSON（AI 可能返回带 markdown 包裹的 JSON）
        let cleanJSON = extractJSON(from: content)

        let result = try AIResponseParser.parse(cleanJSON)
        recordSuccess()
        return result
    }

    /// 测试 API 连接是否正常
    func testConnection() async throws -> String {
        guard let url = URL(string: "\(config.baseURL)/chat/completions") else {
            throw AIServiceError.invalidURL
        }

        let requestBody: [String: Any] = [
            "model": config.model,
            "max_tokens": 10,
            "messages": [
                ["role": "user", "content": "回复OK"]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIServiceError.httpError(code, "连接失败")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? String else {
            return "连接成功"
        }

        return "连接成功，模型: \(model)"
    }

    // MARK: - 截图压缩

    /// 将 PNG 截图压缩为 JPEG，缩放到 640px 宽度
    private func compressScreenshot(_ pngData: Data) -> Data {
        guard let image = NSImage(data: pngData) else { return pngData }

        let targetWidth: CGFloat = 640
        let scale = targetWidth / image.size.width
        let targetHeight = image.size.height * scale

        let resized = NSImage(size: NSSize(width: targetWidth, height: targetHeight))
        resized.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver, fraction: 1.0)
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return pngData
        }

        return jpegData
    }

    // MARK: - JSON 提取

    /// 从 AI 返回内容中提取 JSON（可能被 markdown 代码块包裹）
    private func extractJSON(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 尝试提取 ```json ... ``` 中的内容
        if let jsonStart = trimmed.range(of: "```json"),
           let jsonEnd = trimmed.range(of: "```", range: jsonStart.upperBound..<trimmed.endIndex) {
            return String(trimmed[jsonStart.upperBound..<jsonEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 尝试提取 ``` ... ``` 中的内容
        if let first = trimmed.range(of: "```"),
           let second = trimmed.range(of: "```", range: first.upperBound..<trimmed.endIndex) {
            return String(trimmed[first.upperBound..<second.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 尝试提取 { ... } 中的内容
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }

        return trimmed
    }

    // MARK: - 断路器

    private func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= maxConsecutiveFailures {
            circuitOpenUntil = Date().addingTimeInterval(circuitOpenDuration)
        }
    }

    private func recordSuccess() {
        consecutiveFailures = 0
        circuitOpenUntil = nil
    }
}

// MARK: - 错误类型

enum AIServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case parseError(String)
    case circuitOpen
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "AI API 地址无效"
        case .invalidResponse: return "AI API 返回格式异常"
        case .httpError(let code, let body): return "AI API 错误 (HTTP \(code)): \(body.prefix(100))"
        case .parseError(let msg): return "AI 响应解析失败: \(msg)"
        case .circuitOpen: return "AI 服务暂时不可用（连续失败，60秒后重试）"
        case .notConfigured: return "未配置 AI API Key"
        }
    }
}
