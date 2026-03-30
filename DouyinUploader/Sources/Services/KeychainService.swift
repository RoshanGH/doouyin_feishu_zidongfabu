import Foundation

/// Keychain 操作错误
enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case itemNotFound
    case writeFailed(Error)
    case readFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "安全存储操作失败，状态码: \(status)"
        case .encodingFailed:
            return "数据编码失败"
        case .itemNotFound:
            return "找不到指定项"
        case .writeFailed(let error):
            return "写入失败：\(error.localizedDescription)"
        case .readFailed(let error):
            return "读取失败：\(error.localizedDescription)"
        }
    }
}

/// 安全存储服务 — 使用本地文件替代系统 Keychain
/// 避免每次访问弹出系统密码输入框
///
/// 存储路径: ~/Library/Application Support/com.menggang.douyin-uploader/secrets/
/// 每个 key 对应一个文件，文件内容为 base64 编码的数据
final class KeychainService {

    /// 唯一服务标识符
    static let serviceName = "com.menggang.douyin-uploader"

    /// 自定义存储目录（测试时可注入）
    private static var _customDirectory: URL?

    /// 设置自定义目录（仅测试用）
    static func setCustomDirectory(_ dir: URL?) {
        _customDirectory = dir
    }

    private static var secretsDirectory: URL {
        if let custom = _customDirectory { return custom }
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fallback
        return appSupport
            .appendingPathComponent(serviceName, isDirectory: true)
            .appendingPathComponent("secrets", isDirectory: true)
    }

    private static func ensureDirectoryExists() throws {
        let dir = secretsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// 将 key 转为安全的文件名（白名单过滤，防止路径遍历）
    private static func fileURL(for key: String) -> URL {
        let safeKey = String(key.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)
        })
        let finalKey = safeKey.isEmpty ? "unknown" : safeKey
        return secretsDirectory.appendingPathComponent(finalKey)
    }

    // MARK: - 写入

    @discardableResult
    static func save(key: String, value: String) throws -> Bool {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        return try save(key: key, data: data)
    }

    @discardableResult
    static func save(key: String, data: Data) throws -> Bool {
        do {
            try ensureDirectoryExists()
            // base64 编码后存储（简单的本地混淆，非加密）
            let encoded = data.base64EncodedData()
            try encoded.write(to: fileURL(for: key), options: .atomic)
            return true
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.writeFailed(error)
        }
    }

    // MARK: - 读取

    static func loadString(key: String) throws -> String? {
        guard let data = try load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func load(key: String) throws -> Data? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let encoded = try Data(contentsOf: url)
            guard let data = Data(base64Encoded: encoded) else {
                return nil
            }
            return data
        } catch {
            throw KeychainError.readFailed(error)
        }
    }

    // MARK: - 删除

    static func delete(key: String) throws {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw KeychainError.writeFailed(error)
        }
    }

    // MARK: - 判断是否存在

    static func exists(key: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: key).path)
    }
}

// MARK: - 飞书凭证专用 Key 命名规范

extension KeychainService {
    static func patKey(for configId: UUID) -> String {
        "feishu.pat.\(configId.uuidString)"
    }

    static func appSecretKey(for configId: UUID) -> String {
        "feishu.appSecret.\(configId.uuidString)"
    }
}
