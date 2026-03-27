import Foundation
import Testing
@testable import DouyinUploader

@Suite("FeishuConfig 测试")
struct FeishuConfigTests {

    @Test("默认初始化")
    func defaultInit() {
        let config = FeishuConfig(name: "测试", appToken: "abc", tableId: "tbl123")
        #expect(config.name == "测试")
        #expect(config.appToken == "abc")
        #expect(config.tableId == "tbl123")
        #expect(config.authType == .pat)
        #expect(config.hasPAT == false)
        #expect(config.appId == nil)
        #expect(config.hasAppSecret == false)
        #expect(config.connectionStatus == nil)
    }

    @Test("相等性基于 id")
    func equality() {
        let id = UUID()
        let a = FeishuConfig(id: id, name: "A", appToken: "t1", tableId: "t1")
        let b = FeishuConfig(id: id, name: "B", appToken: "t2", tableId: "t2")
        #expect(a == b)
    }

    @Test("Codable 排除 connectionStatus")
    func codableExcludesConnectionStatus() throws {
        var config = FeishuConfig(name: "编码测试", appToken: "abc", tableId: "tbl")
        config.connectionStatus = .connected(tableName: "表格A", recordCount: 42)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(FeishuConfig.self, from: data)

        #expect(decoded.name == "编码测试")
        #expect(decoded.connectionStatus == nil) // 不持久化
    }

    @Test("FeishuAuthType 编解码")
    func authTypeCodable() throws {
        let pat = FeishuAuthType.pat
        let tenant = FeishuAuthType.tenantApp

        let patData = try JSONEncoder().encode(pat)
        let tenantData = try JSONEncoder().encode(tenant)

        let decodedPat = try JSONDecoder().decode(FeishuAuthType.self, from: patData)
        let decodedTenant = try JSONDecoder().decode(FeishuAuthType.self, from: tenantData)

        #expect(decodedPat == .pat)
        #expect(decodedTenant == .tenantApp)
    }

    @Test("自建应用配置")
    func tenantAppConfig() {
        var config = FeishuConfig(name: "自建", appToken: "abc", tableId: "tbl", authType: .tenantApp)
        config.appId = "cli_xxx"
        config.hasAppSecret = true

        #expect(config.authType == .tenantApp)
        #expect(config.appId == "cli_xxx")
        #expect(config.hasAppSecret == true)
    }
}
