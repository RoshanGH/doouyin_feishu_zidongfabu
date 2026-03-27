import Foundation

/// 单条发布任务（对应飞书表格中的一行）
struct PublishTask: Identifiable, Equatable {
    let id: UUID
    let recordId: String               // 飞书 record_id，回写用
    let douyinAccountId: String         // 抖音号
    let douyinName: String?             // 抖音昵称（飞书表格中的"抖音名称"列）
    let attachments: [FeishuAttachment] // 素材附件列表
    let title: String?                  // 作品标题（图文专用，视频可空）
    let content: String                 // 作品文案
    let tags: [String]                  // 话题标签（已解析，无 # 前缀）
    let musicName: String?              // 音乐名称（nil 或空 = 不加音乐）
    let scheduledTime: Date?            // 定时发布时间（nil = 立即发布）
    var status: PublishStatus           // 发布状态
    var failureReason: String?          // 失败原因

    /// 素材校验结果
    var mediaValidation: MediaValidationResult {
        validateMediaAttachments(attachments)
    }

    /// 是否为视频作品
    var isVideo: Bool {
        if case .validVideo = mediaValidation { return true }
        return false
    }

    /// 是否为图文作品
    var isImagePost: Bool {
        if case .validImages = mediaValidation { return true }
        return false
    }

    /// 是否校验通过
    var isValid: Bool {
        switch mediaValidation {
        case .validVideo, .validImages:
            return true
        case .invalid:
            return false
        }
    }

    /// 是否需要添加音乐
    var hasMusic: Bool {
        guard let musicName else { return false }
        return !musicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 定时发布时间是否已过期
    var isScheduleExpired: Bool {
        guard let scheduledTime else { return false }
        return scheduledTime < Date()
    }

    /// 将话题标签格式化为抖音话题字符串
    /// 输入: ["美食", "探店", "深圳"]
    /// 输出: "#美食 #探店 #深圳"
    var formattedTags: String {
        tags.map {
            let clean = $0.replacingOccurrences(of: " ", with: "")
            return clean.hasPrefix("#") ? clean : "#\(clean)"
        }.joined(separator: " ")
    }

    /// 完整的发布文案（文案 + 话题）
    var fullContent: String {
        if tags.isEmpty {
            return content
        }
        return "\(content)\n\n\(formattedTags)"
    }

    /// 显示名称：优先用抖音名称，没有则用抖音号
    var displayName: String {
        if let name = douyinName, !name.isEmpty {
            return name
        }
        return douyinAccountId
    }

    init(
        id: UUID = UUID(),
        recordId: String,
        douyinAccountId: String,
        douyinName: String? = nil,
        attachments: [FeishuAttachment],
        title: String? = nil,
        content: String,
        tags: [String] = [],
        musicName: String? = nil,
        scheduledTime: Date? = nil,
        status: PublishStatus = .allowPublish,
        failureReason: String? = nil
    ) {
        self.id = id
        self.recordId = recordId
        self.douyinAccountId = douyinAccountId
        self.douyinName = douyinName
        self.attachments = attachments
        self.title = title
        self.content = content
        self.tags = tags
        self.musicName = musicName
        self.scheduledTime = scheduledTime
        self.status = status
        self.failureReason = failureReason
    }
}
