import Foundation
import Testing
@testable import DouyinUploader

@Suite("PublishTask 测试")
struct PublishTaskTests {

    private func makeAttachment(name: String, type: String) -> FeishuAttachment {
        FeishuAttachment(fileToken: "token", name: name, type: type, size: 1024, url: nil)
    }

    // MARK: - 话题标签格式化

    @Test("话题标签格式化：逗号分隔 → #前缀")
    func formattedTags() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [makeAttachment(name: "v.mp4", type: "video/mp4")],
            content: "测试文案",
            tags: ["美食", "探店", "深圳"]
        )
        #expect(task.formattedTags == "#美食 #探店 #深圳")
    }

    @Test("话题标签中空格自动去除")
    func tagsWithSpaces() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [makeAttachment(name: "v.mp4", type: "video/mp4")],
            content: "测试",
            tags: ["美食 探店"]
        )
        #expect(task.formattedTags == "#美食探店")
    }

    // MARK: - 完整发布文案

    @Test("有话题时文案拼接 #话题")
    func fullContentWithTags() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [makeAttachment(name: "v.mp4", type: "video/mp4")],
            content: "今天做了一道菜",
            tags: ["美食", "家常菜"]
        )
        #expect(task.fullContent == "今天做了一道菜\n\n#美食 #家常菜")
    }

    @Test("无话题时文案不变")
    func fullContentWithoutTags() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [makeAttachment(name: "v.mp4", type: "video/mp4")],
            content: "今天做了一道菜"
        )
        #expect(task.fullContent == "今天做了一道菜")
    }

    // MARK: - 素材类型判断

    @Test("视频任务识别正确")
    func videoTask() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [makeAttachment(name: "v.mp4", type: "video/mp4")],
            content: "视频"
        )
        #expect(task.isVideo == true)
        #expect(task.isImagePost == false)
        #expect(task.isValid == true)
    }

    @Test("图文任务识别正确")
    func imageTask() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [
                makeAttachment(name: "a.jpg", type: "image/jpeg"),
                makeAttachment(name: "b.png", type: "image/png"),
            ],
            content: "图文"
        )
        #expect(task.isVideo == false)
        #expect(task.isImagePost == true)
        #expect(task.isValid == true)
    }

    @Test("无效素材任务识别正确")
    func invalidTask() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [],
            content: "空"
        )
        #expect(task.isValid == false)
    }

    // MARK: - 定时发布过期检测

    @Test("未设定时发布不过期")
    func noScheduleNotExpired() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [makeAttachment(name: "v.mp4", type: "video/mp4")],
            content: "test"
        )
        #expect(task.isScheduleExpired == false)
    }

    @Test("过去时间已过期")
    func pastScheduleExpired() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [makeAttachment(name: "v.mp4", type: "video/mp4")],
            content: "test",
            scheduledTime: Date(timeIntervalSinceNow: -3600) // 1小时前
        )
        #expect(task.isScheduleExpired == true)
    }

    @Test("未来时间未过期")
    func futureScheduleNotExpired() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [makeAttachment(name: "v.mp4", type: "video/mp4")],
            content: "test",
            scheduledTime: Date(timeIntervalSinceNow: 3600) // 1小时后
        )
        #expect(task.isScheduleExpired == false)
    }

    // MARK: - 音乐名称

    @Test("音乐名称有值时正确存储")
    func musicNamePresent() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [makeAttachment(name: "v.mp4", type: "video/mp4")],
            content: "test",
            musicName: "草莓不能 创作的原声"
        )
        #expect(task.musicName == "草莓不能 创作的原声")
        #expect(task.hasMusic == true)
    }

    @Test("音乐名称为 nil 时 hasMusic 为 false")
    func musicNameNil() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [makeAttachment(name: "v.mp4", type: "video/mp4")],
            content: "test"
        )
        #expect(task.musicName == nil)
        #expect(task.hasMusic == false)
    }

    @Test("音乐名称为空字符串时 hasMusic 为 false")
    func musicNameEmpty() {
        let task = PublishTask(
            recordId: "rec1",
            douyinAccountId: "dy123",
            attachments: [makeAttachment(name: "v.mp4", type: "video/mp4")],
            content: "test",
            musicName: ""
        )
        #expect(task.hasMusic == false)
    }
}
