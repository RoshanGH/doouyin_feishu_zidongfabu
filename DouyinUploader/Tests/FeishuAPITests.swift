import Foundation
import Testing
@testable import DouyinUploader

@Suite("FeishuAPIError 测试")
struct FeishuAPIErrorTests {

    @Test("所有错误类型都有非空描述")
    func allErrorDescriptions() {
        let errors: [FeishuAPIError] = [
            .networkError(NSError(domain: "test", code: -1)),
            .httpError(statusCode: 401),
            .apiError(code: 99991668, message: "token 无效"),
            .invalidResponse("格式异常"),
            .missingColumn("抖音账号"),
            .downloadFailed("超时")
        ]

        for error in errors {
            let desc = error.errorDescription
            #expect(desc != nil)
            #expect(!desc!.isEmpty)
        }
    }

    @Test("httpError 包含状态码")
    func httpErrorContainsCode() {
        let error = FeishuAPIError.httpError(statusCode: 403)
        #expect(error.errorDescription?.contains("403") == true)
    }

    @Test("apiError 包含错误码和消息")
    func apiErrorContainsCodeAndMessage() {
        let error = FeishuAPIError.apiError(code: 1254043, message: "无权限访问")
        #expect(error.errorDescription?.contains("1254043") == true)
        #expect(error.errorDescription?.contains("无权限访问") == true)
    }

    @Test("missingColumn 包含列名")
    func missingColumnContainsName() {
        let error = FeishuAPIError.missingColumn("作品素材")
        #expect(error.errorDescription?.contains("作品素材") == true)
    }
}

@Suite("FeishuColumn 常量测试")
struct FeishuColumnTests {

    @Test("固定列名完整性")
    func allColumnsPresent() {
        #expect(FeishuColumn.douyinAccount == "抖音账号")
        #expect(FeishuColumn.material == "作品素材")
        #expect(FeishuColumn.title == "作品标题")
        #expect(FeishuColumn.content == "作品文案")
        #expect(FeishuColumn.tags == "话题标签")
        #expect(FeishuColumn.musicName == "音乐名称")
        #expect(FeishuColumn.status == "发布状态")
        #expect(FeishuColumn.publishTime == "发布时间")
        #expect(FeishuColumn.scheduledTime == "定时发布时间")
        #expect(FeishuColumn.failureReason == "失败原因")
    }

    @Test("required 列表包含 10 个列")
    func requiredColumnsCount() {
        #expect(FeishuColumn.required.count == 10)
    }

    @Test("required 列表包含音乐名称")
    func requiredIncludesMusic() {
        #expect(FeishuColumn.required.contains("音乐名称"))
    }
}
