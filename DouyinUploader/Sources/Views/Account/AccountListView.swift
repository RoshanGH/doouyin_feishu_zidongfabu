import SwiftUI

/// 抖音账号列表主页面
struct AccountListView: View {

    @StateObject private var viewModel = AccountViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerBar

            Divider()

            // 账号列表或空状态
            if viewModel.accounts.isEmpty {
                emptyState
            } else {
                accountList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 扫码登录弹窗
        .sheet(isPresented: $viewModel.isLoggingIn) {
            QRCodeLoginView(viewModel: viewModel)
        }
        // 删除确认 Alert
        .alert("删除账号", isPresented: $viewModel.showDeleteConfirm) {
            Button("取消", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("删除", role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            Text("确认删除此抖音账号？删除后该账号的 Cookie 将同时清除，需重新登录。")
        }
        // 错误提示
        .alert("操作失败", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            // 应用启动时检测所有账号 Cookie 有效性
            viewModel.refreshLoginStatus()
        }
    }

    // MARK: - 标题栏

    private var headerBar: some View {
        HStack {
            Text("账号管理")
                .font(.headline)

            if viewModel.isValidating {
                ProgressView()
                    .scaleEffect(0.6)
                    .padding(.leading, 4)
            }

            Spacer()

            Button(action: { viewModel.startLogin() }) {
                Label("添加账号", systemImage: "plus")
                    .font(.body)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .help("扫码登录新抖音账号")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.2.slash")
                .font(.system(size: 52))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("暂无抖音账号")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Text("点击「添加账号」扫码登录，支持管理多个抖音账号")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button("扫码登录") {
                viewModel.startLogin()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 账号列表

    private var accountList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.accounts) { account in
                    AccountRowView(
                        account: account,
                        onRelogin: { viewModel.startLogin() },
                        onDelete: { viewModel.requestDelete(id: account.id) }
                    )

                    Divider()
                        .padding(.leading, 72)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - 账号列表行

/// 账号列表中的单行展示
struct AccountRowView: View {
    let account: DouyinAccount
    let onRelogin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // 头像
            avatarView

            // 账号信息
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // 状态指示灯
                    Circle()
                        .fill(account.isValid ? Color.green : Color.red)
                        .frame(width: 8, height: 8)

                    // 昵称（如果有）
                    if !account.nickname.isEmpty && account.nickname != account.uniqueId {
                        Text(account.nickname)
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    } else {
                        Text("未获取昵称")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }

                // 抖音号（点击复制）
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(account.uniqueId, forType: .string)
                }) {
                    HStack(spacing: 4) {
                        Text("抖音号：\(account.uniqueId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("点击复制抖音号")

                Text("登录时间：\(account.loginTime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // 操作按钮区域
            HStack(spacing: 8) {
                // Cookie 状态标识
                if account.isValid {
                    Label("正常", systemImage: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .labelStyle(.titleAndIcon)
                } else {
                    // 已过期：显示重新登录按钮
                    Button("重新登录") {
                        onRelogin()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.orange)
                }

                // 删除按钮
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("删除账号")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.01))  // 保证点击区域
        .contextMenu {
            Button("重新登录") { onRelogin() }
            Divider()
            Button("删除账号", role: .destructive) { onDelete() }
        }
    }

    // MARK: - 头像视图

    @ViewBuilder
    private var avatarView: some View {
        Group {
            if let avatarUrl = account.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        avatarPlaceholder
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.6)
                    @unknown default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    /// 头像占位图
    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.15))
            Image(systemName: "person.fill")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
        }
    }
}
