import Testing
@testable import DouyinUploader

@Suite("素材类型识别测试")
struct MediaTypeTests {

    // MARK: - MIME 类型识别

    @Test("video/mp4 识别为视频")
    func videoMp4() {
        #expect(MediaType.from(mimeType: "video/mp4") == .video)
    }

    @Test("image/jpeg 识别为图片")
    func imageJpeg() {
        #expect(MediaType.from(mimeType: "image/jpeg") == .image)
    }

    @Test("image/png 识别为图片")
    func imagePng() {
        #expect(MediaType.from(mimeType: "image/png") == .image)
    }

    @Test("application/pdf 不支持")
    func unsupportedMime() {
        #expect(MediaType.from(mimeType: "application/pdf") == nil)
    }

    @Test("大小写不敏感")
    func caseInsensitive() {
        #expect(MediaType.from(mimeType: "VIDEO/MP4") == .video)
        #expect(MediaType.from(mimeType: "Image/JPEG") == .image)
    }

    // MARK: - 扩展名识别

    @Test("jpg 扩展名识别为图片")
    func jpgExtension() {
        #expect(MediaType.from(fileExtension: "jpg") == .image)
    }

    @Test("mp4 扩展名识别为视频")
    func mp4Extension() {
        #expect(MediaType.from(fileExtension: "mp4") == .video)
    }

    @Test("gif 不支持")
    func gifNotSupported() {
        #expect(MediaType.from(fileExtension: "gif") == nil)
    }
}

@Suite("素材校验测试")
struct MediaValidationTests {

    private func makeAttachment(name: String, type: String) -> FeishuAttachment {
        FeishuAttachment(fileToken: "token", name: name, type: type, size: 1024, url: nil)
    }

    @Test("空附件列表返回缺少素材")
    func emptyAttachments() {
        let result = validateMediaAttachments([])
        #expect(result == .invalid(reason: "缺少作品素材"))
    }

    @Test("单个视频附件返回 validVideo")
    func singleVideo() {
        let attachments = [makeAttachment(name: "video.mp4", type: "video/mp4")]
        let result = validateMediaAttachments(attachments)
        #expect(result == .validVideo)
    }

    @Test("多张图片返回 validImages")
    func multipleImages() {
        let attachments = [
            makeAttachment(name: "a.jpg", type: "image/jpeg"),
            makeAttachment(name: "b.png", type: "image/png"),
            makeAttachment(name: "c.webp", type: "image/webp"),
        ]
        let result = validateMediaAttachments(attachments)
        #expect(result == .validImages(count: 3))
    }

    @Test("图片+视频混合返回 invalid")
    func mixedTypes() {
        let attachments = [
            makeAttachment(name: "a.jpg", type: "image/jpeg"),
            makeAttachment(name: "b.mp4", type: "video/mp4"),
        ]
        let result = validateMediaAttachments(attachments)
        #expect(result == .invalid(reason: "素材类型混合，请检查"))
    }

    @Test("多个视频返回 invalid")
    func multipleVideos() {
        let attachments = [
            makeAttachment(name: "a.mp4", type: "video/mp4"),
            makeAttachment(name: "b.mov", type: "video/quicktime"),
        ]
        let result = validateMediaAttachments(attachments)
        #expect(result == .invalid(reason: "不支持多视频，请拆分为多行"))
    }
}
