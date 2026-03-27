import Foundation
import Testing
@testable import DouyinUploader

@Suite("FeishuAttachment 测试")
struct FeishuAttachmentTests {

    @Test("视频附件 MIME 类型")
    func videoAttachment() {
        let att = FeishuAttachment(fileToken: "t1", name: "video.mp4", type: "video/mp4", size: 1024, url: nil)
        #expect(att.type.hasPrefix("video/"))
        #expect(att.name == "video.mp4")
    }

    @Test("图片附件 MIME 类型")
    func imageAttachment() {
        let att = FeishuAttachment(fileToken: "t2", name: "photo.jpg", type: "image/jpeg", size: 512, url: "https://example.com/download")
        #expect(att.type.hasPrefix("image/"))
        #expect(att.url != nil)
    }

    @Test("Codable 编解码（含 file_token 字段映射）")
    func codable() throws {
        let json = """
        {"file_token":"boxcn123","name":"test.png","type":"image/png","size":2048,"url":"https://dl.feishu.cn/xxx"}
        """.data(using: .utf8)!

        let att = try JSONDecoder().decode(FeishuAttachment.self, from: json)
        #expect(att.fileToken == "boxcn123")
        #expect(att.name == "test.png")
        #expect(att.type == "image/png")
        #expect(att.size == 2048)
        #expect(att.url == "https://dl.feishu.cn/xxx")

        // 重新编码
        let data = try JSONEncoder().encode(att)
        let reDecoded = try JSONDecoder().decode(FeishuAttachment.self, from: data)
        #expect(reDecoded == att)
    }

    @Test("url 可为 nil")
    func urlOptional() throws {
        let json = """
        {"file_token":"t","name":"a.mp4","type":"video/mp4","size":100}
        """.data(using: .utf8)!

        let att = try JSONDecoder().decode(FeishuAttachment.self, from: json)
        #expect(att.url == nil)
    }
}
