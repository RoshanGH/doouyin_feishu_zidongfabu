import Foundation
import SwiftUI

/// 飞书配置页面的 ViewModel
/// 负责配置列表的 CRUD、URL 解析以及测试连接
@MainActor
final class FeishuConfigViewModel: ObservableObject {

    // MARK: - Published 属性

    /// 所有配置列表
    @Published var configs: [FeishuConfig] = []

    /// 当前选中的配置（列表中高亮项）
    @Published var selectedConfig: FeishuConfig?

    /// 是否处于编辑模式（编辑已有配置）
    @Published var isEditing: Bool = false

    /// 是否处于新增模式
    @Published var isAdding: Bool = false

    /// 是否正在测试连接
    @Published var isTesting: Bool = false

    /// 测试连接结果描述（nil 表示尚未测试）
    @Published var testResult: String?

    /// 操作错误信息
    @Published var errorMessage: String?

    /// 操作成功提示（自动消失）
    @Published var successMessage: String?

    // MARK: - 编辑表单缓冲区（新增/编辑时使用）

    /// 表单：配置名称
    @Published var formName: String = ""

    /// 表单：飞书 URL（粘贴后自动解析）
    @Published var formURL: String = ""

    /// URL 解析是否成功（控制 App Token / Table ID 字段的显隐）
    @Published var urlParsed: Bool = false

    /// 表单：App Token（从 URL 解析或手动填写）
    @Published var formAppToken: String = ""

    /// 表单：Table ID（从 URL 解析或手动填写）
    @Published var formTableId: String = ""

    /// 表单：认证方式
    @Published var formAuthType: FeishuAuthType = .pat

    /// 表单：PAT（敏感，不持久化到 JSON）
    @Published var formPAT: String = ""

    /// 表单：App ID（自建应用用）
    @Published var formAppId: String = ""

    /// 表单：App Secret（敏感，不持久化到 JSON）
    @Published var formAppSecret: String = ""

    // MARK: - 删除确认

    /// 待删除的配置 ID
    @Published var configToDelete: UUID?

    /// 是否显示删除确认 Alert
    @Published var showDeleteConfirm: Bool = false

    // MARK: - 依赖

    private let store: ConfigStore

    // MARK: - 初始化

    init(store: ConfigStore = ConfigStore()) {
        self.store = store
        loadConfigs()
    }

    // MARK: - 加载配置

    /// 从磁盘加载配置列表
    func loadConfigs() {
        do {
            configs = try store.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 新增配置

    /// 开始新增流程：清空表单、显示新增面板
    func startAdding() {
        clearForm()
        testResult = nil
        isAdding = true
        isEditing = false
    }

    /// 保存新增的配置
    func saveNewConfig() {
        guard validateForm() else { return }

        var newConfig = FeishuConfig(
            name: formName.trimmingCharacters(in: .whitespacesAndNewlines),
            appToken: formAppToken.trimmingCharacters(in: .whitespacesAndNewlines),
            tableId: formTableId.trimmingCharacters(in: .whitespacesAndNewlines),
            authType: formAuthType
        )

        // 保存敏感凭证到 Keychain
        do {
            if formAuthType == .pat, !formPAT.isEmpty {
                try KeychainService.save(key: KeychainService.patKey(for: newConfig.id), value: formPAT)
                newConfig.hasPAT = true
            } else if formAuthType == .tenantApp {
                if !formAppId.isEmpty {
                    newConfig.appId = formAppId
                }
                if !formAppSecret.isEmpty {
                    try KeychainService.save(key: KeychainService.appSecretKey(for: newConfig.id), value: formAppSecret)
                    newConfig.hasAppSecret = true
                }
            }
        } catch {
            errorMessage = "凭证保存失败：\(error.localizedDescription)"
            return
        }

        do {
            try store.add(newConfig)
            configs.append(newConfig)
            selectedConfig = newConfig
            isAdding = false
            clearForm()
            showSuccess("配置已保存")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 编辑配置

    /// 开始编辑指定配置：将现有值填入表单
    func startEditing(config: FeishuConfig) {
        selectedConfig = config
        formName = config.name
        formAppToken = config.appToken
        formTableId = config.tableId
        formAuthType = config.authType
        formAppId = config.appId ?? ""

        // 从 Keychain 读取现有凭证（只读一次用于展示状态）
        formPAT = (try? KeychainService.loadString(key: KeychainService.patKey(for: config.id))) ?? ""
        formAppSecret = (try? KeychainService.loadString(key: KeychainService.appSecretKey(for: config.id))) ?? ""

        testResult = nil
        isEditing = true
        isAdding = false
    }

    /// 保存已编辑的配置
    func saveEditedConfig() {
        guard let original = selectedConfig else { return }
        guard validateForm() else { return }

        var updated = original
        updated.name = formName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.appToken = formAppToken.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tableId = formTableId.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.authType = formAuthType

        // 更新 Keychain 中的敏感凭证
        do {
            if formAuthType == .pat {
                if !formPAT.isEmpty {
                    try KeychainService.save(key: KeychainService.patKey(for: updated.id), value: formPAT)
                    updated.hasPAT = true
                } else {
                    updated.hasPAT = KeychainService.exists(key: KeychainService.patKey(for: updated.id))
                }
                // 清理旧的 App Secret
                try? KeychainService.delete(key: KeychainService.appSecretKey(for: updated.id))
                updated.appId = nil
                updated.hasAppSecret = false
            } else if formAuthType == .tenantApp {
                updated.appId = formAppId.isEmpty ? nil : formAppId
                if !formAppSecret.isEmpty {
                    try KeychainService.save(key: KeychainService.appSecretKey(for: updated.id), value: formAppSecret)
                    updated.hasAppSecret = true
                } else {
                    updated.hasAppSecret = KeychainService.exists(key: KeychainService.appSecretKey(for: updated.id))
                }
                // 清理旧的 PAT
                try? KeychainService.delete(key: KeychainService.patKey(for: updated.id))
                updated.hasPAT = false
            }
        } catch {
            errorMessage = "凭证更新失败：\(error.localizedDescription)"
            return
        }

        do {
            try store.update(updated)
            // 不可变更新：用新值替换列表中的旧值
            configs = configs.map { $0.id == updated.id ? updated : $0 }
            selectedConfig = updated
            isEditing = false
            clearForm()
            showSuccess("配置已更新")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 取消编辑/新增
    func cancelEditing() {
        isEditing = false
        isAdding = false
        clearForm()
        testResult = nil
    }

    // MARK: - 删除配置

    /// 发起删除确认
    func requestDelete(id: UUID) {
        configToDelete = id
        showDeleteConfirm = true
    }

    /// 确认删除
    func confirmDelete() {
        guard let id = configToDelete else { return }

        do {
            try store.delete(id: id)
            configs = configs.filter { $0.id != id }
            if selectedConfig?.id == id {
                selectedConfig = configs.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        configToDelete = nil
        showDeleteConfirm = false
    }

    // MARK: - 测试连接

    /// 测试当前表单中填写的配置是否可以正常连接飞书
    func testConnection() {
        guard !formAppToken.isEmpty, !formTableId.isEmpty else {
            testResult = "请先填写 App Token 和 Table ID"
            return
        }

        // 构造临时配置用于测试
        var tempConfig = FeishuConfig(
            name: "测试",
            appToken: formAppToken.trimmingCharacters(in: .whitespacesAndNewlines),
            tableId: formTableId.trimmingCharacters(in: .whitespacesAndNewlines),
            authType: formAuthType
        )

        // 将临时凭证写入 Keychain（测试完成后清理）
        let tempId = tempConfig.id
        var needsCleanup = false

        do {
            if formAuthType == .pat, !formPAT.isEmpty {
                try KeychainService.save(key: KeychainService.patKey(for: tempId), value: formPAT)
                tempConfig.hasPAT = true
                needsCleanup = true
            } else if formAuthType == .tenantApp, !formAppSecret.isEmpty {
                tempConfig.appId = formAppId.isEmpty ? nil : formAppId
                try KeychainService.save(key: KeychainService.appSecretKey(for: tempId), value: formAppSecret)
                tempConfig.hasAppSecret = true
                needsCleanup = true
            }
        } catch {
            testResult = "凭证准备失败：\(error.localizedDescription)"
            return
        }

        isTesting = true
        testResult = nil

        Task {
            defer {
                // 无论成功失败，清理临时 Keychain 条目
                if needsCleanup {
                    try? KeychainService.delete(key: KeychainService.patKey(for: tempId))
                    try? KeychainService.delete(key: KeychainService.appSecretKey(for: tempId))
                }
                self.isTesting = false
            }

            do {
                let api = FeishuAPI(config: tempConfig)
                let count = try await api.testConnection()
                self.testResult = "连接成功，待发布记录数：\(count)"
            } catch {
                self.testResult = "连接失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - URL 解析

    /// 粘贴飞书 URL 时自动解析 appToken 和 tableId（供 View 的 .onChange 调用）
    func parseURLIfNeeded() {
        let trimmed = formURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            urlParsed = false
            return
        }

        if let result = parseFeishuURL(trimmed) {
            formAppToken = result.appToken
            if let tableId = result.tableId {
                formTableId = tableId
            }
            urlParsed = true
        } else {
            urlParsed = false
        }
    }

    // MARK: - 表单验证

    /// 验证表单字段是否合法
    /// - Returns: 验证通过返回 true，失败时设置 errorMessage 并返回 false
    private func validateForm() -> Bool {
        let name = formName.trimmingCharacters(in: .whitespacesAndNewlines)
        let appToken = formAppToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let tableId = formTableId.trimmingCharacters(in: .whitespacesAndNewlines)

        if name.isEmpty {
            errorMessage = "请填写配置名称"
            return false
        }
        if appToken.isEmpty {
            errorMessage = "请填写 App Token（可通过粘贴飞书 URL 自动解析）"
            return false
        }
        if tableId.isEmpty {
            errorMessage = "请填写 Table ID（可通过粘贴飞书 URL 自动解析）"
            return false
        }

        if formAuthType == .pat && formPAT.isEmpty {
            // 编辑时允许不填（保留原有 PAT）
            if isAdding {
                errorMessage = "PAT 认证需要填写个人访问令牌"
                return false
            }
        }

        if formAuthType == .tenantApp {
            if formAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "自建应用认证需要填写 App ID"
                return false
            }
            if isAdding && formAppSecret.isEmpty {
                errorMessage = "自建应用认证需要填写 App Secret"
                return false
            }
        }

        errorMessage = nil
        return true
    }

    // MARK: - 辅助方法

    /// 清空表单字段
    private func clearForm() {
        formName = ""
        formURL = ""
        formAppToken = ""
        formTableId = ""
        formAuthType = .pat
        formPAT = ""
        formAppId = ""
        formAppSecret = ""
        errorMessage = nil
    }

    private func showSuccess(_ message: String) {
        successMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if successMessage == message {
                successMessage = nil
            }
        }
    }
}
