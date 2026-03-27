import Foundation

/// 飞书认证方式
enum FeishuAuthType: String, Codable {
    case pat = "pat"
    case tenantApp = "tenant_app"
}

/// 飞书多维表格配置
struct FeishuConfig: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var appToken: String
    var tableId: String
    var authType: FeishuAuthType
    var createdAt: Date

    /// PAT（存 Keychain，这里只保留标记是否已配置）
    var hasPAT: Bool

    /// 自建应用 App ID（非敏感，可明文存储）
    var appId: String?

    /// 自建应用 App Secret 是否已配置（Secret 本身存 Keychain）
    var hasAppSecret: Bool

    /// 连接状态（不持久化，运行时检测）
    var connectionStatus: ConnectionStatus?

    enum ConnectionStatus: Equatable {
        case connected(tableName: String, recordCount: Int)
        case failed(message: String)
        case checking
    }

    init(
        id: UUID = UUID(),
        name: String,
        appToken: String,
        tableId: String,
        authType: FeishuAuthType = .pat,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.appToken = appToken
        self.tableId = tableId
        self.authType = authType
        self.createdAt = createdAt
        self.hasPAT = false
        self.appId = nil
        self.hasAppSecret = false
        self.connectionStatus = nil
    }

    // Codable — 排除 connectionStatus（运行时状态）
    enum CodingKeys: String, CodingKey {
        case id, name, appToken, tableId, authType, createdAt, hasPAT, appId, hasAppSecret
    }

    static func == (lhs: FeishuConfig, rhs: FeishuConfig) -> Bool {
        lhs.id == rhs.id
    }

    /// Hashable 实现：只基于 id，connectionStatus 不参与哈希
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
