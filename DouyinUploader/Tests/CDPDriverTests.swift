import Testing
import Foundation
@testable import DouyinUploader

/// CDPDriverImpl 基本构造测试
@Suite("CDPDriverImpl 测试")
struct CDPDriverTests {

    // MARK: - 构造

    @Test("CDPDriverImpl 可以用 CDPClient 构造")
    func canBeInitializedWithClient() {
        let client = CDPClient()
        let driver = CDPDriverImpl(client: client)
        // 构造成功即通过，无需额外断言
        _ = driver
    }

    @Test("CDPDriverImpl 遵守 CDPDriver 协议")
    func conformsToCDPDriverProtocol() {
        let client = CDPClient()
        let driver: any CDPDriver = CDPDriverImpl(client: client)
        _ = driver
    }
}
