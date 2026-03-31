import Foundation

/// AI 返回的操作指令
enum AIAction: Equatable {
    case click(x: Int, y: Int)
    case type(text: String)
    case pressKey(key: String)
    case uploadFile(paths: [String])
    case scroll(direction: String, amount: Int)
    case wait(seconds: Int)
    case waitForUser(message: String)
    case completed(message: String)
    case error(message: String)
}

/// AI 分析页面后的完整结果
struct AIAnalysisResult: Equatable {
    /// 页面状态
    let status: PageStatus
    /// 需要执行的操作
    let action: AIAction
    /// AI 对当前页面的描述
    let description: String

    enum PageStatus: String, Equatable {
        case normal          // 正常页面，可操作
        case popup           // 有弹窗遮挡
        case captcha         // 验证码
        case loginExpired    // 登录过期
        case uploadComplete  // 上传完成
        case publishSuccess  // 发布成功
        case error           // 异常状态
    }
}

/// AI 配置
struct AIConfig: Equatable {
    let baseURL: String
    let apiKey: String
    let model: String

    static let defaultBaseURL = "https://apicn.unifyllm.top/v1"
    static let defaultModel = "claude-sonnet-4-6"
}
