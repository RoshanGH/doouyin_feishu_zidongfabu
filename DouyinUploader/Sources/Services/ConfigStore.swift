import Foundation

/// ConfigStore 相关错误
enum ConfigStoreError: LocalizedError {
    case directoryCreationFailed(Error)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case writeFailed(Error)
    case readFailed(Error)
    case configNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let error):
            return "无法创建配置目录：\(error.localizedDescription)"
        case .encodingFailed(let error):
            return "配置序列化失败：\(error.localizedDescription)"
        case .decodingFailed(let error):
            return "配置解析失败：\(error.localizedDescription)"
        case .writeFailed(let error):
            return "写入配置文件失败：\(error.localizedDescription)"
        case .readFailed(let error):
            return "读取配置文件失败：\(error.localizedDescription)"
        case .configNotFound(let id):
            return "找不到 ID 为 \(id) 的配置"
        }
    }
}

/// 飞书配置的持久化存储
/// 存储路径: ~/Library/Application Support/com.menggang.douyin-uploader/configs.json
/// 注意：PAT 和 App Secret 等敏感信息存于 Keychain，JSON 文件中只存非敏感字段
final class ConfigStore {

    // MARK: - 存储路径

    /// Application Support 目录下的配置文件路径
    private static let appBundleId = "com.menggang.douyin-uploader"

    /// 获取配置目录 URL（不保证目录存在）
    static func configDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(appBundleId, isDirectory: true)
    }

    /// 获取配置文件 URL
    static func configFileURL() -> URL {
        configDirectory().appendingPathComponent("configs.json")
    }

    // MARK: - 实例属性（支持测试时注入自定义路径）

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter fileURL: 配置文件路径（nil 时使用默认路径）
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ConfigStore.configFileURL()

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - 目录初始化

    /// 确保配置目录存在（首次运行自动创建）
    private func ensureDirectoryExists() throws {
        let dir = fileURL.deletingLastPathComponent()
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw ConfigStoreError.directoryCreationFailed(error)
        }
    }

    // MARK: - 加载

    /// 从磁盘加载全部配置
    /// - Returns: 配置数组，文件不存在时返回空数组
    /// - Throws: ConfigStoreError
    func load() throws -> [FeishuConfig] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ConfigStoreError.readFailed(error)
        }

        do {
            return try decoder.decode([FeishuConfig].self, from: data)
        } catch {
            throw ConfigStoreError.decodingFailed(error)
        }
    }

    // MARK: - 保存（全量覆写）

    /// 将配置数组写入磁盘（全量覆写）
    /// - Parameter configs: 要持久化的配置列表
    /// - Throws: ConfigStoreError
    func save(_ configs: [FeishuConfig]) throws {
        try ensureDirectoryExists()

        let data: Data
        do {
            data = try encoder.encode(configs)
        } catch {
            throw ConfigStoreError.encodingFailed(error)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ConfigStoreError.writeFailed(error)
        }
    }

    // MARK: - 单条增删改

    /// 新增一条配置（如果 ID 已存在则忽略）
    /// - Parameter config: 新配置
    /// - Throws: ConfigStoreError
    func add(_ config: FeishuConfig) throws {
        var configs = try load()
        // 幂等：ID 重复时不重复添加
        guard !configs.contains(where: { $0.id == config.id }) else { return }
        configs.append(config)
        try save(configs)
    }

    /// 更新一条已存在的配置
    /// - Parameter config: 更新后的配置（根据 id 匹配）
    /// - Throws: ConfigStoreError（找不到时抛出 configNotFound）
    func update(_ config: FeishuConfig) throws {
        var configs = try load()
        guard let index = configs.firstIndex(where: { $0.id == config.id }) else {
            throw ConfigStoreError.configNotFound(config.id)
        }
        // 不可变模式：用新值替换旧值
        configs = configs.enumerated().map { i, c in i == index ? config : c }
        try save(configs)
    }

    /// 删除指定 ID 的配置，同时清理 Keychain 中的敏感凭证
    /// - Parameter id: 要删除的配置 ID
    /// - Throws: ConfigStoreError
    func delete(id: UUID) throws {
        var configs = try load()
        configs = configs.filter { $0.id != id }
        try save(configs)

        // 清理 Keychain 中的敏感数据（忽略清理失败，不阻断流程）
        try? KeychainService.delete(key: KeychainService.patKey(for: id))
        try? KeychainService.delete(key: KeychainService.appSecretKey(for: id))
    }
}
