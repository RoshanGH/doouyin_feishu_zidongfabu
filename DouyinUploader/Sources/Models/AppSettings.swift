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
}
