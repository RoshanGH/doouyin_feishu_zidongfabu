import Foundation

/// SettingsManager 相关错误
enum SettingsManagerError: LocalizedError {
    case directoryCreationFailed(Error)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case writeFailed(Error)
    case readFailed(Error)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let error):
            return "无法创建配置目录：\(error.localizedDescription)"
        case .encodingFailed(let error):
            return "设置序列化失败：\(error.localizedDescription)"
        case .decodingFailed(let error):
            return "设置解析失败：\(error.localizedDescription)"
        case .writeFailed(let error):
            return "写入设置文件失败：\(error.localizedDescription)"
        case .readFailed(let error):
            return "读取设置文件失败：\(error.localizedDescription)"
        }
    }
}

/// App 设置的持久化管理
/// 存储路径: ~/Library/Application Support/com.menggang.douyin-uploader/settings.json
final class SettingsManager {

    // MARK: - 路径

    private static let appBundleId = "com.menggang.douyin-uploader"

    static func appSupportDirectory() -> URL {
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fallback
        return appSupport.appendingPathComponent(appBundleId, isDirectory: true)
    }

    static func settingsFileURL() -> URL {
        appSupportDirectory().appendingPathComponent("settings.json")
    }

    // MARK: - 实例

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter fileURL: 自定义文件路径（nil 时使用默认路径，方便测试注入）
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? SettingsManager.settingsFileURL()

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
    }

    // MARK: - 目录初始化

    private func ensureDirectoryExists() throws {
        let dir = fileURL.deletingLastPathComponent()
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw SettingsManagerError.directoryCreationFailed(error)
        }
    }

    // MARK: - 加载

    /// 从磁盘加载设置，文件不存在时返回默认值
    func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            // 文件损坏时返回默认值，不阻断启动
            return AppSettings()
        }
    }

    // MARK: - 保存

    /// 将设置写入磁盘
    /// - Throws: SettingsManagerError
    func save(_ settings: AppSettings) throws {
        try ensureDirectoryExists()

        let data: Data
        do {
            data = try encoder.encode(settings)
        } catch {
            throw SettingsManagerError.encodingFailed(error)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw SettingsManagerError.writeFailed(error)
        }
    }
}
