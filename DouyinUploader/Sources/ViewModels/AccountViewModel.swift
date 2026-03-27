import Foundation
import SwiftUI

/// 账号管理页面的 ViewModel
/// 负责账号列表展示、扫码登录流程、Cookie 有效性检测
@MainActor
final class AccountViewModel: ObservableObject {

    // MARK: - Published 属性

    /// 账号列表
    @Published var accounts: [DouyinAccount] = []

    /// 是否正在进行登录流程（显示二维码弹窗时为 true）
    @Published var isLoggingIn: Bool = false

    /// 当前二维码图片 URL（AsyncImage 使用）
    @Published var qrCodeImageURL: String?

    /// 登录流程状态描述（显示在二维码弹窗中）
    @Published var loginStatus: String = "正在获取二维码..."

    /// 操作错误信息
    @Published var errorMessage: String?

    /// 待删除的账号 ID（确认弹窗使用）
    @Published var accountToDelete: UUID?

    /// 是否显示删除确认 Alert
    @Published var showDeleteConfirm: Bool = false

    /// 是否正在检测 Cookie 有效性
    @Published var isValidating: Bool = false

    // MARK: - 私有状态

    /// 当前登录轮询 Task（用于取消）
    private var loginTask: Task<Void, Never>?

    /// 轮询间隔：2 秒
    private let pollInterval: UInt64 = 2_000_000_000

    /// 最大轮询次数：5 分钟 / 2 秒 = 150 次
    private let maxPollCount: Int = 150

    // MARK: - 依赖

    private let store: AccountStore
    private let loginService: DouyinLoginService
    private let cookieManager: DouyinCookieManager

    // MARK: - 初始化

    init(
        store: AccountStore = AccountStore(),
        loginService: DouyinLoginService = DouyinLoginService(),
        cookieManager: DouyinCookieManager = DouyinCookieManager()
    ) {
        self.store = store
        self.loginService = loginService
        self.cookieManager = cookieManager
        loadAccounts()
    }

    // MARK: - 加载账号列表

    /// 从磁盘加载账号列表
    func loadAccounts() {
        do {
            accounts = try store.loadAll()
        } catch {
            errorMessage = "加载账号列表失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 扫码登录

    /// 开始登录流程：打开 WebView 登录弹窗
    func startLogin() {
        isLoggingIn = true
        loginStatus = ""
        errorMessage = nil
    }

    /// 取消登录流程
    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        isLoggingIn = false
        qrCodeImageURL = nil
        loginStatus = "正在获取二维码..."
    }

    /// WebView 登录成功回调 — 从 WKWebView 获取 Cookie + 从 DOM 提取的用户信息
    func handleWebViewLoginSuccess(cookies: [HTTPCookie], nickname: String, douyinId: String, avatarUrl: String?) {
        // 使用从页面提取的抖音号，如果提取失败则用 Cookie 中的 uid 或时间戳
        let finalDouyinId = douyinId.isEmpty ? "dy_\(Int(Date().timeIntervalSince1970))" : douyinId
        let finalNickname = nickname.isEmpty ? (douyinId.isEmpty ? "未知用户" : douyinId) : nickname

        loginStatus = "正在保存登录信息..."

        loginTask = Task {
            do {
                // 保存 Cookie 到 Keychain
                try cookieManager.saveCookies(uniqueId: finalDouyinId, cookies: cookies)

                let userInfo = DouyinUserInfo(uniqueId: finalDouyinId, nickname: finalNickname, avatarUrl: avatarUrl)
                try cookieManager.saveUserInfo(uniqueId: finalDouyinId, userInfo: userInfo)

                // 保存账号到磁盘
                let account = DouyinAccount(
                    uniqueId: finalDouyinId,
                    nickname: finalNickname,
                    avatarUrl: avatarUrl,
                    loginTime: Date(),
                    isValid: true
                )
                try store.add(account)

                // 更新列表
                accounts = accounts.filter { $0.uniqueId != account.uniqueId } + [account]

                loginStatus = "登录成功！"
                try await Task.sleep(nanoseconds: 1_000_000_000)
                isLoggingIn = false
            } catch {
                errorMessage = error.localizedDescription
                loginStatus = "保存失败：\(error.localizedDescription)"
            }
        }
    }

    /// 完整登录流程（旧的 SSO API 方式，已弃用）
    private func performLoginFlow() async {
        do {
            // 获取二维码
            let (imageURL, token) = try await loginService.getQRCode()
            qrCodeImageURL = imageURL
            loginStatus = "请用抖音 App 扫描二维码"

            // 开始轮询扫码状态
            let redirectURL = try await pollQRStatus(token: token)

            // 用户确认后，完成登录获取 Cookie
            loginStatus = "正在完成登录..."
            let cookies = try await loginService.completeLogin(redirectURL: redirectURL)

            // 获取用户信息
            loginStatus = "正在获取用户信息..."
            let userInfo = try await loginService.fetchUserInfo(cookies: cookies)

            // 保存 Cookie 到 Keychain
            try cookieManager.saveCookies(uniqueId: userInfo.uniqueId, cookies: cookies)
            try cookieManager.saveUserInfo(uniqueId: userInfo.uniqueId, userInfo: userInfo)

            // 保存账号到磁盘
            let account = DouyinAccount(
                uniqueId: userInfo.uniqueId,
                nickname: userInfo.nickname,
                avatarUrl: userInfo.avatarUrl,
                loginTime: Date(),
                isValid: true
            )
            try store.add(account)

            // 更新内存中的列表（不可变模式：过滤掉旧的同 uniqueId 账号再添加）
            accounts = accounts.filter { $0.uniqueId != account.uniqueId } + [account]

            loginStatus = "登录成功！"
            // 短暂展示成功状态后自动关闭弹窗
            try await Task.sleep(nanoseconds: 1_500_000_000)
            isLoggingIn = false
            qrCodeImageURL = nil

        } catch is CancellationError {
            // 用户主动取消，不处理
        } catch {
            errorMessage = error.localizedDescription
            loginStatus = "登录失败"
            // 失败后保留弹窗，让用户可以重试
        }
    }

    /// 轮询二维码扫码状态，直到确认或超时
    /// - Parameter token: 二维码 token
    /// - Returns: 确认登录后的 redirectURL
    /// - Throws: DouyinLoginError 或 CancellationError
    private func pollQRStatus(token: String) async throws -> String {
        var pollCount = 0

        while pollCount < maxPollCount {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: pollInterval)
            try Task.checkCancellation()

            pollCount += 1
            let status = try await loginService.checkQRConnect(token: token)

            switch status {
            case .waiting:
                loginStatus = "请用抖音 App 扫描二维码"
            case .scanned:
                loginStatus = "已扫码，请在手机上确认登录"
            case .confirmed(let redirectURL):
                return redirectURL
            case .expired:
                // 二维码过期：自动刷新
                loginStatus = "二维码已过期，正在刷新..."
                let (newImageURL, newToken) = try await loginService.getQRCode()
                qrCodeImageURL = newImageURL
                loginStatus = "请用抖音 App 扫描二维码"
                // 递归调用，使用新 token 继续轮询
                return try await pollQRStatus(token: newToken)
            }
        }

        // 超过最大轮询次数，视为超时
        throw DouyinLoginError.qrCheckFailed("登录超时（超过 5 分钟），请重新扫码")
    }

    // MARK: - 删除账号

    /// 发起删除确认
    /// - Parameter id: 要删除的账号 ID
    func requestDelete(id: UUID) {
        accountToDelete = id
        showDeleteConfirm = true
    }

    /// 确认删除账号（含 Keychain Cookie 联动清理）
    func confirmDelete() {
        guard let id = accountToDelete else { return }

        do {
            try store.delete(id: id)
            accounts = accounts.filter { $0.id != id }
        } catch {
            errorMessage = "删除账号失败：\(error.localizedDescription)"
        }

        accountToDelete = nil
        showDeleteConfirm = false
    }

    /// 取消删除
    func cancelDelete() {
        accountToDelete = nil
        showDeleteConfirm = false
    }

    // MARK: - Cookie 有效性检测

    /// 启动时检测所有账号的 Cookie 有效性，更新 isValid 状态
    func refreshLoginStatus() {
        guard !accounts.isEmpty else { return }
        isValidating = true

        Task {
            var updatedAccounts = accounts

            await withTaskGroup(of: (Int, Bool).self) { group in
                for (index, account) in updatedAccounts.enumerated() {
                    group.addTask {
                        let isValid = await self.loginService.validateCookies(uniqueId: account.uniqueId)
                        return (index, isValid)
                    }
                }

                for await (index, isValid) in group {
                    updatedAccounts[index] = DouyinAccount(
                        id: updatedAccounts[index].id,
                        uniqueId: updatedAccounts[index].uniqueId,
                        nickname: updatedAccounts[index].nickname,
                        avatarUrl: updatedAccounts[index].avatarUrl,
                        loginTime: updatedAccounts[index].loginTime,
                        isValid: isValid
                    )
                }
            }

            // 更新内存和磁盘状态
            accounts = updatedAccounts
            try? store.save(updatedAccounts)
            isValidating = false
        }
    }
}
