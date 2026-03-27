import Foundation
import Testing
@testable import DouyinUploader

@Suite("DouyinAccount 测试")
struct DouyinAccountTests {

    @Test("默认值初始化正确")
    func defaultInit() {
        let account = DouyinAccount(uniqueId: "dy123", nickname: "测试号")
        #expect(account.uniqueId == "dy123")
        #expect(account.nickname == "测试号")
        #expect(account.avatarUrl == nil)
        #expect(account.isValid == true)
    }

    @Test("完整初始化正确")
    func fullInit() {
        let date = Date()
        let account = DouyinAccount(
            uniqueId: "dy456",
            nickname: "美食号",
            avatarUrl: "https://example.com/avatar.jpg",
            loginTime: date,
            isValid: false
        )
        #expect(account.uniqueId == "dy456")
        #expect(account.nickname == "美食号")
        #expect(account.avatarUrl == "https://example.com/avatar.jpg")
        #expect(account.loginTime == date)
        #expect(account.isValid == false)
    }

    @Test("相等性基于 id 而非属性")
    func equality() {
        let id = UUID()
        let a = DouyinAccount(id: id, uniqueId: "dy1", nickname: "A")
        let b = DouyinAccount(id: id, uniqueId: "dy2", nickname: "B")
        #expect(a == b)
    }

    @Test("不同 id 不相等")
    func inequality() {
        let a = DouyinAccount(uniqueId: "dy1", nickname: "A")
        let b = DouyinAccount(uniqueId: "dy1", nickname: "A")
        #expect(a != b)
    }

    @Test("Codable 编解码")
    func codable() throws {
        let original = DouyinAccount(
            uniqueId: "dyfx750",
            nickname: "探店号",
            avatarUrl: "https://example.com/img.jpg",
            loginTime: Date(timeIntervalSince1970: 1711432800),
            isValid: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DouyinAccount.self, from: data)
        #expect(decoded.uniqueId == original.uniqueId)
        #expect(decoded.nickname == original.nickname)
        #expect(decoded.avatarUrl == original.avatarUrl)
    }
}
