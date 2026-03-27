import Foundation

/// 飞书多维表格附件字段中的单个附件
struct FeishuAttachment: Codable, Equatable {
    let fileToken: String
    let name: String
    let type: String      // MIME 类型，如 "video/mp4", "image/jpeg"
    let size: Int         // 字节大小
    let url: String?      // 临时下载 URL（有时效性）

    enum CodingKeys: String, CodingKey {
        case fileToken = "file_token"
        case name, type, size, url
    }
}
