import Testing
@testable import DouyinUploader

@Suite("PublishStatus 状态机测试")
struct PublishStatusTests {

    // MARK: - isPending 测试

    @Test("允许发布是待执行状态")
    func allowPublishIsPending() {
        #expect(PublishStatus.allowPublish.isPending == true)
    }

    @Test("发布失败是待执行状态")
    func publishFailedIsPending() {
        #expect(PublishStatus.publishFailed.isPending == true)
    }

    @Test("发布中是待执行状态（孤儿任务恢复）")
    func publishingIsPending() {
        #expect(PublishStatus.publishing.isPending == true)
    }

    @Test("已发布不是待执行状态")
    func publishedIsNotPending() {
        #expect(PublishStatus.published.isPending == false)
    }

    // MARK: - isFinal 测试

    @Test("已发布是终态")
    func publishedIsFinal() {
        #expect(PublishStatus.published.isFinal == true)
    }

    @Test("其他状态不是终态")
    func nonPublishedIsNotFinal() {
        #expect(PublishStatus.allowPublish.isFinal == false)
        #expect(PublishStatus.publishing.isFinal == false)
        #expect(PublishStatus.publishFailed.isFinal == false)
    }

    // MARK: - 状态转换合法性测试

    @Test("允许发布 → 发布中：合法")
    func allowToPublishing() {
        #expect(PublishStatus.allowPublish.canTransition(to: .publishing) == true)
    }

    @Test("发布中 → 已发布：合法")
    func publishingToPublished() {
        #expect(PublishStatus.publishing.canTransition(to: .published) == true)
    }

    @Test("发布中 → 发布失败：合法")
    func publishingToFailed() {
        #expect(PublishStatus.publishing.canTransition(to: .publishFailed) == true)
    }

    @Test("发布失败 → 发布中（重试）：合法")
    func failedToPublishing() {
        #expect(PublishStatus.publishFailed.canTransition(to: .publishing) == true)
    }

    @Test("发布中 → 发布中（孤儿恢复）：合法")
    func publishingToPublishing() {
        #expect(PublishStatus.publishing.canTransition(to: .publishing) == true)
    }

    @Test("已发布 → 任何状态：非法")
    func publishedCannotTransition() {
        #expect(PublishStatus.published.canTransition(to: .allowPublish) == false)
        #expect(PublishStatus.published.canTransition(to: .publishing) == false)
        #expect(PublishStatus.published.canTransition(to: .publishFailed) == false)
    }

    @Test("允许发布 → 已发布（跳过发布中）：非法")
    func allowToPublishedIsInvalid() {
        #expect(PublishStatus.allowPublish.canTransition(to: .published) == false)
    }

    // MARK: - rawValue 与飞书单选值一致

    @Test("rawValue 与飞书单选选项文本完全一致")
    func rawValuesMatchFeishu() {
        #expect(PublishStatus.allowPublish.rawValue == "允许发布")
        #expect(PublishStatus.publishing.rawValue == "发布中")
        #expect(PublishStatus.published.rawValue == "已发布")
        #expect(PublishStatus.publishFailed.rawValue == "发布失败")
    }
}
