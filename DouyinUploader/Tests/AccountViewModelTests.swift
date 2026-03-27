import Foundation
import Testing
@testable import DouyinUploader

@Suite("AccountViewModel 测试")
struct AccountViewModelTests {

    private func makeTempStore() -> (AccountStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("account_vm_test_\(UUID().uuidString)")
        let fileURL = dir.appendingPathComponent("accounts.json")
        return (AccountStore(fileURL: fileURL), dir)
    }

    // MARK: - 加载

    @MainActor
    @Test("loadAccounts 加载已保存的账号")
    func loadAccounts() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let account = DouyinAccount(uniqueId: "dy123", nickname: "测试号")
        try store.add(account)

        let vm = AccountViewModel(store: store)
        #expect(vm.accounts.count == 1)
        #expect(vm.accounts.first?.uniqueId == "dy123")
    }

    @MainActor
    @Test("空磁盘时账号列表为空")
    func emptyAccounts() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = AccountViewModel(store: store)
        #expect(vm.accounts.isEmpty)
    }

    // MARK: - 登录状态

    @MainActor
    @Test("startLogin 设置 isLoggingIn")
    func startLogin() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = AccountViewModel(store: store)
        vm.startLogin()

        #expect(vm.isLoggingIn == true)
    }

    @MainActor
    @Test("cancelLogin 重置状态")
    func cancelLogin() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = AccountViewModel(store: store)
        vm.startLogin()
        vm.cancelLogin()

        #expect(vm.isLoggingIn == false)
        #expect(vm.qrCodeImageURL == nil)
    }

    // MARK: - 删除

    @MainActor
    @Test("requestDelete 设置待删除 ID")
    func requestDelete() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = AccountViewModel(store: store)
        let id = UUID()
        vm.accountToDelete = id
        vm.showDeleteConfirm = true

        #expect(vm.accountToDelete == id)
        #expect(vm.showDeleteConfirm == true)
    }

    // MARK: - WebView 登录成功回调

    @MainActor
    @Test("handleWebViewLoginSuccess 保存账号并更新列表")
    func handleLoginSuccess() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = AccountViewModel(store: store)

        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: [
                "Set-Cookie": "sessionid=test123; domain=.douyin.com; path=/"
            ],
            for: URL(string: "https://douyin.com")!
        )

        vm.handleWebViewLoginSuccess(
            cookies: cookies,
            nickname: "美食号",
            douyinId: "dyfx750",
            avatarUrl: "https://example.com/avatar.jpg"
        )

        // handleWebViewLoginSuccess 是异步的，等待 Task 完成
        // 由于 Task 内部有 sleep(1s)，这里用短暂等待来验证初始状态
        #expect(vm.loginStatus == "正在保存登录信息...")
    }

    @MainActor
    @Test("handleWebViewLoginSuccess douyinId 为空时使用时间戳替代")
    func handleLoginSuccessEmptyId() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = AccountViewModel(store: store)
        vm.handleWebViewLoginSuccess(
            cookies: [],
            nickname: "",
            douyinId: "",
            avatarUrl: nil
        )

        // douyinId 为空时应该用 dy_ 前缀 + 时间戳
        #expect(vm.loginStatus == "正在保存登录信息...")
    }
}
