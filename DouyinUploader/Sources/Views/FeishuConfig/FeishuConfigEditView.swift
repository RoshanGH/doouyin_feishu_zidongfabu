import SwiftUI

/// 编辑/新增飞书配置的表单视图
struct FeishuConfigEditView: View {

    /// 表单模式
    enum Mode {
        case adding   // 新增
        case editing  // 编辑已有配置
    }

    @ObservedObject var viewModel: FeishuConfigViewModel
    let mode: Mode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 标题
                HStack {
                    Text(mode == .adding ? "新增飞书配置" : "编辑飞书配置")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                }

                Divider()

                // 基本信息区
                formSection(title: "基本信息") {
                    // 配置名称
                    FormField(label: "配置名称", required: true) {
                        TextField("例如：内容团队主表", text: $viewModel.formName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // 飞书 URL 粘贴框
                    FormField(label: "飞书 URL", required: true, hint: "粘贴飞书多维表格链接，自动解析 App Token 和 Table ID") {
                        TextField("https://xxx.feishu.cn/wiki/xxx?table=tbl...", text: $viewModel.formURL)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: viewModel.formURL) { _ in
                                viewModel.parseURLIfNeeded()
                            }
                    }

                    // URL 解析结果提示
                    if viewModel.urlParsed {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已解析：App Token = \(viewModel.formAppToken), Table ID = \(viewModel.formTableId)")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else if !viewModel.formURL.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("无法从 URL 中解析，请手动填写下方字段")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    // App Token 和 Table ID — 仅在 URL 解析失败时显示手动输入
                    if !viewModel.urlParsed {
                        FormField(label: "App Token", required: true, hint: "多维表格的唯一标识符") {
                            TextField("BascXXXXXX", text: $viewModel.formAppToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        FormField(label: "Table ID", required: true, hint: "表格 ID，以 tbl 开头") {
                            TextField("tblXXXXXX", text: $viewModel.formTableId)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                // 认证方式区
                formSection(title: "认证方式") {
                    Picker("认证方式", selection: $viewModel.formAuthType) {
                        Text("PAT（个人访问令牌）").tag(FeishuAuthType.pat)
                        Text("自建应用").tag(FeishuAuthType.tenantApp)
                    }
                    .pickerStyle(.radioGroup)

                    // PAT 认证字段
                    if viewModel.formAuthType == .pat {
                        FormField(label: "个人访问令牌", required: mode == .adding, hint: "在飞书开发者平台「用户身份验证」中生成") {
                            TextField(
                                mode == .editing ? "如不修改请留空" : "pat-xxxxxxxx",
                                text: $viewModel.formPAT
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        }
                    }

                    // 自建应用认证字段
                    if viewModel.formAuthType == .tenantApp {
                        FormField(label: "App ID", required: true, hint: "飞书开发者后台的应用 ID") {
                            TextField("cli_xxxxxxxx", text: $viewModel.formAppId)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        FormField(label: "App Secret", required: mode == .adding, hint: "飞书开发者后台的应用密钥") {
                            TextField(
                                mode == .editing ? "如不修改请留空" : "xxxxxxxxxxxxxxxx",
                                text: $viewModel.formAppSecret
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                // 测试连接区
                testConnectionSection

                // 错误提示
                if let error = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .padding(.horizontal, 4)
                }

                // 操作按钮
                actionButtons

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 测试连接区域

    private var testConnectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("连接测试")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: { viewModel.testConnection() }) {
                    HStack(spacing: 6) {
                        if viewModel.isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text(viewModel.isTesting ? "测试中..." : "测试连接")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isTesting)

                // 测试结果展示
                if let result = viewModel.testResult {
                    HStack(spacing: 6) {
                        Image(systemName: result.hasPrefix("连接成功") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.hasPrefix("连接成功") ? .green : .red)
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.hasPrefix("连接成功") ? .green : .red)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("取消") {
                viewModel.cancelEditing()
            }
            .keyboardShortcut(.escape)

            Button(mode == .adding ? "添加" : "保存") {
                if mode == .adding {
                    viewModel.saveNewConfig()
                } else {
                    viewModel.saveEditedConfig()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
        }
    }

    // MARK: - 辅助：分区容器

    @ViewBuilder
    private func formSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
    }
}

// MARK: - 表单字段组件

/// 带标签、提示文字的表单字段包装器
struct FormField<Content: View>: View {
    let label: String
    var required: Bool = false
    var hint: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if required {
                    Text("*")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }

            content()

            if let hint = hint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
