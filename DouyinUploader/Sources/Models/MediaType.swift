import Foundation

/// 素材类型 — 根据飞书附件的 MIME 类型自动识别
enum MediaType: Equatable {
    case video
    case image

    /// 从 MIME 类型字符串判断素材类型
    static func from(mimeType: String) -> MediaType? {
        let lower = mimeType.lowercased()
        if lower.hasPrefix("video/") {
            return .video
        } else if lower.hasPrefix("image/") {
            return .image
        }
        return nil
    }

    /// 支持的图片扩展名
    static let supportedImageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]

    /// 支持的视频扩展名
    static let supportedVideoExtensions: Set<String> = ["mp4", "mov"]

    /// 所有支持的扩展名
    static let allSupportedExtensions: Set<String> = supportedImageExtensions.union(supportedVideoExtensions)

    /// 从文件扩展名判断素材类型
    static func from(fileExtension ext: String) -> MediaType? {
        let lower = ext.lowercased()
        if supportedImageExtensions.contains(lower) {
            return .image
        } else if supportedVideoExtensions.contains(lower) {
            return .video
        }
        return nil
    }
}

/// 素材校验结果
enum MediaValidationResult: Equatable {
    case validVideo
    case validImages(count: Int)
    case invalid(reason: String)
}

/// 校验一组附件的素材类型
func validateMediaAttachments(_ attachments: [FeishuAttachment]) -> MediaValidationResult {
    guard !attachments.isEmpty else {
        return .invalid(reason: "缺少作品素材")
    }

    var images: [FeishuAttachment] = []
    var videos: [FeishuAttachment] = []
    var unsupported: [String] = []

    for attachment in attachments {
        guard let mediaType = MediaType.from(mimeType: attachment.type) else {
            let ext = (attachment.name as NSString).pathExtension
            if !MediaType.allSupportedExtensions.contains(ext.lowercased()) {
                unsupported.append(ext)
            }
            continue
        }
        switch mediaType {
        case .image:
            images.append(attachment)
        case .video:
            videos.append(attachment)
        }
    }

    if !unsupported.isEmpty {
        return .invalid(reason: "不支持的文件格式（\(unsupported.joined(separator: ", "))）")
    }

    if !images.isEmpty && !videos.isEmpty {
        return .invalid(reason: "素材类型混合，请检查")
    }

    if videos.count > 1 {
        return .invalid(reason: "不支持多视频，请拆分为多行")
    }

    if videos.count == 1 {
        return .validVideo
    }

    return .validImages(count: images.count)
}
