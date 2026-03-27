import Foundation

/// 发布状态枚举 — 飞书表格中的单选字段值
/// 状态机转换规则：
///   允许发布 → 发布中 → 已发布
///                    → 发布失败 → (下次执行时自动纳入重试)
///   发布中（孤儿）→ (下次执行时自动纳入重试)
enum PublishStatus: String, Codable, CaseIterable {
    case allowPublish = "允许发布"
    case publishing = "发布中"
    case published = "已发布"
    case publishFailed = "发布失败"

    /// 是否为待执行状态（读取飞书时的筛选条件）
    var isPending: Bool {
        switch self {
        case .allowPublish, .publishFailed, .publishing:
            return true
        case .published:
            return false
        }
    }

    /// 是否为终态（不可再变更）
    var isFinal: Bool {
        self == .published
    }

    /// 检查状态转换是否合法
    func canTransition(to target: PublishStatus) -> Bool {
        switch (self, target) {
        case (.allowPublish, .publishing):
            return true
        case (.publishing, .published):
            return true
        case (.publishing, .publishFailed):
            return true
        case (.publishFailed, .publishing):
            return true
        // 孤儿任务：发布中 → 发布中（重新执行）
        case (.publishing, .publishing):
            return true
        default:
            return false
        }
    }
}
