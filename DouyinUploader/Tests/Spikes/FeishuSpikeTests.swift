import XCTest
@testable import DouyinUploader

/// Spike S6 + S7 + S8: 飞书 API 验证
/// ⚠️ 需要真实的 PAT 和飞书表格才能运行
/// 运行前设置环境变量：
///   FEISHU_PAT=pat-xxx
///   FEISHU_APP_TOKEN=VwGhbXXX
///   FEISHU_TABLE_ID=tblYYY
final class FeishuSpikeTests: XCTestCase {

    private var pat: String?
    private var appToken: String?
    private var tableId: String?

    override func setUp() {
        super.setUp()
        pat = ProcessInfo.processInfo.environment["FEISHU_PAT"]
        appToken = ProcessInfo.processInfo.environment["FEISHU_APP_TOKEN"]
        tableId = ProcessInfo.processInfo.environment["FEISHU_TABLE_ID"]
    }

    /// S6: 飞书 API 读取记录
    func test_S6_fetchRecords() async throws {
        try XCTSkipIf(pat == nil || appToken == nil || tableId == nil,
                      "需要环境变量 FEISHU_PAT, FEISHU_APP_TOKEN, FEISHU_TABLE_ID")

        var config = FeishuConfig(name: "spike", appToken: appToken!, tableId: tableId!)
        config.hasPAT = true
        try KeychainService.save(key: KeychainService.patKey(for: config.id), value: pat!)
        defer { try? KeychainService.delete(key: KeychainService.patKey(for: config.id)) }

        let api = FeishuAPI(config: config)
        let records = try await api.fetchRecords()

        print("✅ S6: 成功获取 \(records.count) 条记录")
        XCTAssertTrue(records.count >= 0, "应该能获取到记录（0 条也算成功，表示 API 通了）")

        // 验证字段结构
        if let first = records.first {
            print("  第一条记录字段: \(first.fields.keys.sorted())")
            XCTAssertNotNil(first.recordId)
        }
    }

    /// S7: 飞书 API 写入记录
    func test_S7_updateRecord() async throws {
        try XCTSkipIf(pat == nil || appToken == nil || tableId == nil,
                      "需要环境变量 FEISHU_PAT, FEISHU_APP_TOKEN, FEISHU_TABLE_ID")

        // 注意：此测试会修改飞书表格数据，请在测试表格上运行
        print("⚠️ S7: 写入测试需要手动验证飞书表格是否更新")
        print("  如需测试，请取消注释下方代码并指定 record_id")

        // var config = FeishuConfig(name: "spike", appToken: appToken!, tableId: tableId!)
        // config.hasPAT = true
        // try KeychainService.save(key: KeychainService.patKey(for: config.id), value: pat!)
        //
        // let api = FeishuAPI(config: config)
        // try await api.updateRecord(recordId: "recXXX", fields: ["失败原因": "Spike Test 写入验证"])
        // print("✅ S7: 写入成功")
    }

    /// S8: 飞书附件下载
    func test_S8_downloadAttachment() async throws {
        try XCTSkipIf(pat == nil || appToken == nil || tableId == nil,
                      "需要环境变量 FEISHU_PAT, FEISHU_APP_TOKEN, FEISHU_TABLE_ID")

        print("⚠️ S8: 附件下载测试需要手动指定 file_token")
        print("  如需测试，请取消注释下方代码并指定 file_token")

        // var config = FeishuConfig(name: "spike", appToken: appToken!, tableId: tableId!)
        // config.hasPAT = true
        // try KeychainService.save(key: KeychainService.patKey(for: config.id), value: pat!)
        //
        // let api = FeishuAPI(config: config)
        // let localURL = try await api.downloadAttachment(fileToken: "boxcnXXX", fileName: "test.mp4")
        // let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
        // let size = attrs[.size] as? Int ?? 0
        // print("✅ S8: 下载成功，文件大小: \(size) bytes")
        // XCTAssertTrue(size > 0)
        // try FileManager.default.removeItem(at: localURL)
    }
}
