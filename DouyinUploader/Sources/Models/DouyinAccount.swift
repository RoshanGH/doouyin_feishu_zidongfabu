import Foundation

/// 抖音账号模型
struct DouyinAccount: Identifiable, Codable, Equatable {
    let id: UUID
    let uniqueId: String      // 抖音号，如 dyfx750s5c44
    var nickname: String       // 昵称
    var avatarUrl: String?     // 头像 URL
    var loginTime: Date        // 登录时间
    var isValid: Bool          // Cookie 是否有效（运行时检测）

    init(
        id: UUID = UUID(),
        uniqueId: String,
        nickname: String,
        avatarUrl: String? = nil,
        loginTime: Date = Date(),
        isValid: Bool = true
    ) {
        self.id = id
        self.uniqueId = uniqueId
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.loginTime = loginTime
        self.isValid = isValid
    }

    static func == (lhs: DouyinAccount, rhs: DouyinAccount) -> Bool {
        lhs.id == rhs.id
    }
}
