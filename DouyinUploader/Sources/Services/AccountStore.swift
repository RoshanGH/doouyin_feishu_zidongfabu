import Foundation

/// AccountStore 相关错误
enum AccountStoreError: LocalizedError {
    case directoryCreationFailed(Error)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case writeFailed(Error)
    case readFailed(Error)
    case accountNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let error):
            return "无法创建账号数据目录：\(error.localizedDescription)"
        case .encodingFailed(let error):
            return "账号数据序列化失败：\(error.localizedDescription)"
        case .decodingFailed(let error):
            return "账号数据解析失败：\(error.localizedDescription)"
        case .writeFailed(let error):
            return "写入账号文件失败：\(error.localizedDescription)"
        case .readFailed(let error):
            return "读取账号文件失败：\(error.localizedDescription)"
        case .accountNotFound(let id):
            return "找不到 ID 为 \(id) 的账号"
        }
    }
}

/// 抖音账号的持久化存储
/// 存储路径: ~/Library/Application Support/com.menggang.douyin-uploader/accounts.json
/// 注意：Cookie 等敏感信息存于 Keychain，JSON 文件中只存非敏感字段（昵称、头像 URL、登录时间等）
final class AccountStore {

    // MARK: - 存储路径

    private static let appBundleId = "com.menggang.douyin-uploader"

    /// 获取账号数据目录 URL
    static func accountDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent(appBundleId, isDirectory: true)
    }

    /// 获取账号文件 URL
    static func accountFileURL() -> URL {
        accountDirectory().appendingPathComponent("accounts.json")
    }

    // MARK: - 实例属性（支持测试时注入自定义路径）

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let cookieManager: DouyinCookieManager

    /// - Parameters:
    ///   - fileURL: 账号文件路径（nil 时使用默认路径）
    ///   - cookieManager: Cookie 管理器（nil 时使用默认实例）
    init(fileURL: URL? = nil, cookieManager: DouyinCookieManager = DouyinCookieManager()) {
        self.fileURL = fileURL ?? AccountStore.accountFileURL()
        self.cookieManager = cookieManager

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - 目录初始化

    /// 确保账号数据目录存在（首次运行自动创建）
    private func ensureDirectoryExists() throws {
        let dir = fileURL.deletingLastPathComponent()
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw AccountStoreError.directoryCreationFailed(error)
        }
    }

    // MARK: - 加载

    /// 从磁盘加载所有账号（非敏感信息）
    /// - Returns: 账号数组，文件不存在时返回空数组
    /// - Throws: AccountStoreError
    func loadAll() throws -> [DouyinAccount] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw AccountStoreError.readFailed(error)
        }

        do {
            return try decoder.decode([DouyinAccount].self, from: data)
        } catch {
            throw AccountStoreError.decodingFailed(error)
        }
    }

    // MARK: - 保存（全量覆写）

    /// 将账号数组全量写入磁盘
    /// - Parameter accounts: 要持久化的账号列表
    /// - Throws: AccountStoreError
    func save(_ accounts: [DouyinAccount]) throws {
        try ensureDirectoryExists()

        let data: Data
        do {
            data = try encoder.encode(accounts)
        } catch {
            throw AccountStoreError.encodingFailed(error)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw AccountStoreError.writeFailed(error)
        }
    }

    // MARK: - 单条增删改

    /// 新增一个账号（如果 uniqueId 已存在则更新）
    /// - Parameter account: 新账号
    /// - Throws: AccountStoreError
    func add(_ account: DouyinAccount) throws {
        var accounts = try loadAll()
        // 如果相同 uniqueId 已存在，替换旧记录
        if let index = accounts.firstIndex(where: { $0.uniqueId == account.uniqueId }) {
            accounts = accounts.enumerated().map { i, a in i == index ? account : a }
        } else {
            accounts.append(account)
        }
        try save(accounts)
    }

    /// 更新一条已存在的账号记录
    /// - Parameter account: 更新后的账号（根据 id 匹配）
    /// - Throws: AccountStoreError（找不到时抛出 accountNotFound）
    func update(_ account: DouyinAccount) throws {
        var accounts = try loadAll()
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw AccountStoreError.accountNotFound(account.id)
        }
        // 不可变模式：用新值替换旧值
        accounts = accounts.enumerated().map { i, a in i == index ? account : a }
        try save(accounts)
    }

    /// 删除指定 ID 的账号，同时联动清理 Keychain 中的 Cookie
    /// - Parameter id: 要删除的账号 ID
    /// - Throws: AccountStoreError
    func delete(id: UUID) throws {
        var accounts = try loadAll()

        // 找到要删除的账号，以获取其 uniqueId 用于清理 Keychain
        let accountToDelete = accounts.first(where: { $0.id == id })

        accounts = accounts.filter { $0.id != id }
        try save(accounts)

        // 联动清理 Keychain 中的 Cookie（忽略清理失败）
        if let uniqueId = accountToDelete?.uniqueId {
            cookieManager.deleteAll(uniqueId: uniqueId)
        }
    }
}
