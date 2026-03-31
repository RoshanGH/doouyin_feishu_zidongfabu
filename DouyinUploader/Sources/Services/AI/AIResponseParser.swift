import Foundation

/// 解析 AI 返回的 JSON 为 AIAnalysisResult
enum AIResponseParser {

    enum ParseError: LocalizedError {
        case invalidJSON
        case missingField(String)
        case unknownActionType(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON: return "AI 返回的不是有效 JSON"
            case .missingField(let f): return "AI 返回缺少字段: \(f)"
            case .unknownActionType(let t): return "AI 返回了未知操作类型: \(t)"
            }
        }
    }

    /// 解析 AI 返回的 JSON 字符串
    static func parse(_ jsonString: String) throws -> AIAnalysisResult {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }

        // 解析 status
        let statusStr = json["status"] as? String ?? "normal"
        let status = AIAnalysisResult.PageStatus(rawValue: statusStr) ?? .normal

        // 解析 description
        let description = json["description"] as? String ?? ""

        // 解析 action
        guard let actionDict = json["action"] as? [String: Any],
              let actionType = actionDict["type"] as? String else {
            throw ParseError.missingField("action.type")
        }

        let action = try parseAction(type: actionType, dict: actionDict)

        return AIAnalysisResult(status: status, action: action, description: description)
    }

    /// 解析单个 action
    private static func parseAction(type: String, dict: [String: Any]) throws -> AIAction {
        switch type {
        case "click":
            guard let x = (dict["x"] as? Int) ?? (dict["x"] as? Double).map(Int.init),
                  let y = (dict["y"] as? Int) ?? (dict["y"] as? Double).map(Int.init) else {
                throw ParseError.missingField("action.x/y")
            }
            return .click(x: x, y: y)

        case "type":
            let text = dict["text"] as? String ?? ""
            return .type(text: text)

        case "pressKey":
            let key = dict["key"] as? String ?? "Enter"
            return .pressKey(key: key)

        case "uploadFile":
            let paths = dict["paths"] as? [String] ?? []
            return .uploadFile(paths: paths)

        case "scroll":
            let direction = dict["direction"] as? String ?? "down"
            let amount = dict["amount"] as? Int ?? 300
            return .scroll(direction: direction, amount: amount)

        case "wait":
            let seconds = dict["seconds"] as? Int ?? 2
            return .wait(seconds: seconds)

        case "waitForUser":
            let message = dict["message"] as? String ?? "请手动操作"
            return .waitForUser(message: message)

        case "completed":
            let message = dict["message"] as? String ?? "操作完成"
            return .completed(message: message)

        case "error":
            let message = dict["message"] as? String ?? "未知错误"
            return .error(message: message)

        default:
            throw ParseError.unknownActionType(type)
        }
    }

    /// 校验坐标是否在页面可视区域内
    static func isValidCoordinate(x: Int, y: Int, viewportWidth: Int, viewportHeight: Int) -> Bool {
        return x >= 0 && x <= viewportWidth && y >= 0 && y <= viewportHeight
    }
}
