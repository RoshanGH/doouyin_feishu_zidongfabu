import SwiftUI

/// 飞书配置列表主页面
/// 左侧显示配置列表，右侧显示编辑/新增表单
struct FeishuConfigListView: View {

    @StateObject private var viewModel = FeishuConfigViewModel()

    var body: some View {
        HSplitView {
            // 左侧：配置列表面板
            configListPanel
                .frame(minWidth: 240, maxWidth: 300)

            // 右侧：编辑/新增/详情面板
            rightPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 删除确认弹窗
        .alert("删除配置", isPresented: $viewModel.showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            Text("确认删除此飞书配置？删除后无法恢复，相关凭证也将同时清除。")
        }
    }

    // MARK: - 左侧列表面板

    private var configListPanel: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("飞书配置")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.startAdding() }) {
                    Image(systemName: "plus")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help("新增飞书配置")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 配置列表
            if viewModel.configs.isEmpty {
                emptyState
            } else {
                List(viewModel.configs, selection: $viewModel.selectedConfig) { config in
                    ConfigRowView(
                        config: config,
                        isSelected: viewModel.selectedConfig?.id == config.id,
                        onEdit: { viewModel.startEditing(config: config) },
                        onDelete: { viewModel.requestDelete(id: config.id) }
                    )
                    .tag(config)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tablecells")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("暂无飞书配置")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("点击右上角「+」按钮添加配置")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("添加第一个配置") {
                viewModel.startAdding()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - 右侧面板

    @ViewBuilder
    private var rightPanel: some View {
        if viewModel.isAdding {
            FeishuConfigEditView(viewModel: viewModel, mode: .adding)
        } else if viewModel.isEditing, viewModel.selectedConfig != nil {
            FeishuConfigEditView(viewModel: viewModel, mode: .editing)
        } else if let config = viewModel.selectedConfig {
            ConfigDetailView(config: config, onEdit: {
                viewModel.startEditing(config: config)
            })
        } else {
            // 未选中状态
            VStack(spacing: 12) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("从左侧选择一个配置")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 配置列表行

/// 列表中的单行配置展示
struct ConfigRowView: View {
    let config: FeishuConfig
    let isSelected: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 连接状态圆点
            connectionStatusDot

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.body)
                    .lineLimit(1)
                Text(authTypeLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("编辑") { onEdit() }
            Divider()
            Button("删除", role: .destructive) { onDelete() }
        }
    }

    /// 认证方式标签
    private var authTypeLabel: String {
        switch config.authType {
        case .pat: return "PAT 认证"
        case .tenantApp: return "自建应用"
        }
    }

    /// 连接状态指示圆点
    @ViewBuilder
    private var connectionStatusDot: some View {
        switch config.connectionStatus {
        case .connected:
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        case .failed:
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        case .checking:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 8, height: 8)
        case nil:
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - 配置详情视图（只读）

/// 查看配置详情（非编辑状态）
struct ConfigDetailView: View {
    let config: FeishuConfig
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题区域
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(config.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("创建于 \(config.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("编辑") { onEdit() }
                        .buttonStyle(.borderedProminent)
                }

                Divider()

                // 连接信息
                GroupBox("连接信息") {
                    VStack(alignment: .leading, spacing: 10) {
                        DetailRow(label: "App Token", value: config.appToken)
                        DetailRow(label: "Table ID", value: config.tableId)
                        DetailRow(label: "认证方式", value: config.authType == .pat ? "PAT（个人访问令牌）" : "自建应用")
                        if config.authType == .tenantApp, let appId = config.appId {
                            DetailRow(label: "App ID", value: appId)
                        }
                        DetailRow(
                            label: "凭证状态",
                            value: credentialStatus,
                            valueColor: credentialOK ? .green : .orange
                        )
                    }
                    .padding(8)
                }

                // 连接状态
                if let status = config.connectionStatus {
                    GroupBox("连接状态") {
                        connectionStatusView(status: status)
                            .padding(8)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
    }

    private var credentialOK: Bool {
        config.authType == .pat ? config.hasPAT : (config.hasAppSecret && config.appId != nil)
    }

    private var credentialStatus: String {
        if config.authType == .pat {
            return config.hasPAT ? "PAT 已配置" : "PAT 未配置"
        } else {
            if config.appId == nil { return "App ID 未配置" }
            return config.hasAppSecret ? "App Secret 已配置" : "App Secret 未配置"
        }
    }

    @ViewBuilder
    private func connectionStatusView(status: FeishuConfig.ConnectionStatus) -> some View {
        switch status {
        case .connected(_, let recordCount):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("连接正常")
                    .foregroundColor(.green)
                Spacer()
                Text("记录数：\(recordCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .failed(let message):
            HStack(alignment: .top) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        case .checking:
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("检测中...")
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 通用详情行

/// 键值对展示行
struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)
                .font(.body)
            Text(value)
                .foregroundColor(valueColor)
                .font(.body)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
