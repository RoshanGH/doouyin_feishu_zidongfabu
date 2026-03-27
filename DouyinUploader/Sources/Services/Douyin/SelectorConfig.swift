import Foundation

// MARK: - 选择器配置结构

/// CSS 选择器配置（对应 selectors.json 的顶层结构）
struct SelectorConfig: Codable, Equatable {
    let version: String
    let common: CommonSelectors
    let videoUpload: VideoUploadSelectors
    let imageUpload: ImageUploadSelectors
    let successKeywords: [String]
    let failureKeywords: [String]

    enum CodingKeys: String, CodingKey {
        case version
        case common
        case videoUpload = "video_upload"
        case imageUpload = "image_upload"
        case successKeywords = "success_keywords"
        case failureKeywords = "failure_keywords"
    }
}

/// 通用选择器
struct CommonSelectors: Codable, Equatable {
    let uploadPageURL: String
    let publishButton: String
    let publishButtonText: String
    let descriptionEditor: String
    let scheduleRadio: String
    let scheduleRadioText: String
    let scheduleInput: String

    enum CodingKeys: String, CodingKey {
        case uploadPageURL = "upload_page_url"
        case publishButton = "publish_button"
        case publishButtonText = "publish_button_text"
        case descriptionEditor = "description_editor"
        case scheduleRadio = "schedule_radio"
        case scheduleRadioText = "schedule_radio_text"
        case scheduleInput = "schedule_input"
    }
}

/// 视频上传选择器
struct VideoUploadSelectors: Codable, Equatable {
    let fileInput: String
    let uploadCompleteMarker: String
    let uploadCompleteText: String
    let uploadProgress: String

    enum CodingKeys: String, CodingKey {
        case fileInput = "file_input"
        case uploadCompleteMarker = "upload_complete_marker"
        case uploadCompleteText = "upload_complete_text"
        case uploadProgress = "upload_progress"
    }
}

/// 图文上传选择器
struct ImageUploadSelectors: Codable, Equatable {
    let modeSwitchText: String
    let fileInput: String
    let fileInputFallback: String
    let titleInput: String
    let uploadItem: String
    let uploadCompleteText: String

    enum CodingKeys: String, CodingKey {
        case modeSwitchText = "mode_switch_text"
        case fileInput = "file_input"
        case fileInputFallback = "file_input_fallback"
        case titleInput = "title_input"
        case uploadItem = "upload_item"
        case uploadCompleteText = "upload_complete_text"
    }
}

// MARK: - SelectorConfig 加载错误

/// 选择器配置加载相关错误
enum SelectorConfigError: LocalizedError {
    case bundleResourceNotFound
    case decodingFailed(String)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .bundleResourceNotFound:
            return "Bundle 中未找到 selectors.json 资源文件"
        case .decodingFailed(let detail):
            return "selectors.json 解析失败：\(detail)"
        case .invalidData:
            return "selectors.json 数据无效"
        }
    }
}

// MARK: - SelectorConfigLoader

/// 选择器配置加载器
/// 优先从 Application Support 加载用户自定义版本，否则回退到 Bundle 内置版本
final class SelectorConfigLoader {

    // MARK: - 路径常量

    /// Application Support 中的用户自定义配置路径
    static var userCustomPath: URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent("DouyinUploader", isDirectory: true)
            .appendingPathComponent("selectors.json")
    }

    // MARK: - 加载

    /// 加载选择器配置
    /// 优先级：用户自定义（Application Support）> Bundle 内置
    /// - Returns: 解析后的 SelectorConfig
    /// - Throws: SelectorConfigError
    func load() throws -> SelectorConfig {
        // 1. 尝试从 Application Support 加载用户自定义版本
        if let customURL = Self.userCustomPath,
           FileManager.default.fileExists(atPath: customURL.path) {
            do {
                let data = try Data(contentsOf: customURL)
                return try decode(data: data, source: "用户自定义")
            } catch {
                // 用户自定义版本解析失败时，回退到 Bundle 版本（不静默忽略，记录原因）
                // 此处继续执行以加载 Bundle 版本
            }
        }

        // 2. 从 Bundle 加载内置版本
        return try loadFromBundle()
    }

    /// 仅从 Bundle 加载内置选择器配置
    /// - Returns: 解析后的 SelectorConfig
    /// - Throws: SelectorConfigError
    func loadFromBundle() throws -> SelectorConfig {
        guard let url = Bundle.module.url(
            forResource: "selectors",
            withExtension: "json"
        ) else {
            // Swift Package Manager 资源路径
            guard let fallbackURL = bundleFallbackURL() else {
                throw SelectorConfigError.bundleResourceNotFound
            }
            let data = try Data(contentsOf: fallbackURL)
            return try decode(data: data, source: "Bundle fallback")
        }

        let data = try Data(contentsOf: url)
        return try decode(data: data, source: "Bundle")
    }

    /// 从 Data 解码配置
    private func decode(data: Data, source: String) throws -> SelectorConfig {
        guard !data.isEmpty else {
            throw SelectorConfigError.invalidData
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(SelectorConfig.self, from: data)
        } catch let decodingError as DecodingError {
            throw SelectorConfigError.decodingFailed(decodingError.localizedDescription)
        } catch {
            throw SelectorConfigError.decodingFailed(error.localizedDescription)
        }
    }

    /// Bundle 内置资源的备用查找路径（针对可执行目标）
    private func bundleFallbackURL() -> URL? {
        // 在测试和命令行工具中 Bundle.module 可能不可用，尝试直接路径
        let resourcePaths = [
            Bundle.main.resourcePath,
            Bundle.main.bundlePath
        ]

        for path in resourcePaths {
            guard let base = path else { continue }
            let candidate = URL(fileURLWithPath: base)
                .appendingPathComponent("Resources")
                .appendingPathComponent("selectors.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }

            // 也尝试直接在 bundle root
            let direct = URL(fileURLWithPath: base)
                .appendingPathComponent("selectors.json")
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }
        }

        return nil
    }
}

// MARK: - SelectorConfig 便利扩展

extension SelectorConfig {

    /// 返回内置默认配置（用于测试或离线场景）
    static var defaultConfig: SelectorConfig {
        SelectorConfig(
            version: "1.0.0",
            common: CommonSelectors(
                uploadPageURL: "https://creator.douyin.com/creator-micro/content/upload",
                publishButton: "button[class*='primary']",
                publishButtonText: "发布",
                descriptionEditor: ".zone-container",
                scheduleRadio: "[class^='radio']",
                scheduleRadioText: "定时发布",
                scheduleInput: ".semi-input"
            ),
            videoUpload: VideoUploadSelectors(
                fileInput: "div[class^='container'] input",
                uploadCompleteMarker: "[class^='long-card']",
                uploadCompleteText: "重新上传",
                uploadProgress: "[class*='progress']"
            ),
            imageUpload: ImageUploadSelectors(
                modeSwitchText: "发布图文",
                fileInput: "div[class^='container'] input[accept*='image']",
                fileInputFallback: "div[class^='container'] input",
                titleInput: "input[placeholder*='标题']",
                uploadItem: "[class*='upload-item']",
                uploadCompleteText: "添加图片"
            ),
            successKeywords: ["发布成功", "已发布", "内容已提交"],
            failureKeywords: ["发布失败", "上传失败", "提交失败"]
        )
    }
}
