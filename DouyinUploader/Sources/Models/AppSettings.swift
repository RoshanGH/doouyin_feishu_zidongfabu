import Foundation

/// App 全局设置
struct AppSettings: Codable, Equatable {
    /// 任务间隔最小秒
    var taskIntervalMin: Double = 5
    /// 任务间隔最大秒
    var taskIntervalMax: Double = 15
    /// JS 操作延迟最小秒
    var jsDelayMin: Double = 0.5
    /// JS 操作延迟最大秒
    var jsDelayMax: Double = 2.0
    /// 单账号批量上限
    var batchLimit: Int = 10
    /// 达到上限后等待分钟
    var batchWaitMinutes: Int = 5
    /// 日志保留天数
    var logRetentionDays: Int = 30
    /// 执行完成通知
    var enableNotification: Bool = true
    /// 防休眠
    var preventSleep: Bool = true
    /// 调试模式（开启后发布时显示浏览器窗口，可观察发布过程）
    var debugMode: Bool = false
    /// 是否完成引导
    var hasCompletedOnboarding: Bool = false

    // MARK: - AI 配置

    /// AI 模式
    var aiMode: AIMode = .off
    /// AI API 转发地址
    var aiBaseURL: String = AIConfig.defaultBaseURL
    /// AI 模型名称
    var aiModel: String = AIConfig.defaultModel
}

/// AI 模式
enum AIMode: String, Codable, CaseIterable, Equatable {
    case off = "off"              // 关闭 AI，走旧逻辑
    case popupOnly = "popup_only" // 仅弹窗检测
    case full = "full"            // 完整 AI 驱动

    var displayName: String {
        switch self {
        case .off: return "关闭"
        case .popupOnly: return "仅弹窗检测"
        case .full: return "完整 AI 驱动"
        }
    }
}
