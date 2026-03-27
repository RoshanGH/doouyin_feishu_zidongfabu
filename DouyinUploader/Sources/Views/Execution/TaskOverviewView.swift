import SwiftUI

/// 执行概览面板
/// 展示：任务分类统计、涉及账号、登录状态、开始/取消按钮
struct TaskOverviewView: View {
    @ObservedObject var viewModel: ExecutionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // 标题
                Text("执行概览")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.top, 4)

                // 任务统计卡片
                taskStatsSection

                Divider()

                // 账号登录状态
                accountStatusSection

                Spacer(minLength: 16)

                // 操作按钮
                actionButtons
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 任务统计区块

    @ViewBuilder
    private var taskStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("待执行任务")
                .font(.headline)

            // 视频任务数
            let videoCount = viewModel.validTasks.filter { $0.isVideo }.count
            // 图文任务数
            let imageCount = viewModel.validTasks.filter { $0.isImagePost }.count
            // 校验失败数
            let invalidCount = viewModel.invalidTasks.count

            HStack {
                StatBadge(value: videoCount, label: "视频", color: .blue)
                StatBadge(value: imageCount, label: "图文", color: .purple)
                if invalidCount > 0 {
                    StatBadge(value: invalidCount, label: "无效", color: .red)
                }
            }

            if invalidCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("\(invalidCount) 条任务因校验失败或定时时间过期被跳过")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - 账号状态区块

    @ViewBuilder
    private var accountStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("涉及账号")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.requiredAccounts.count) 个")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            if viewModel.requiredAccounts.isEmpty {
                Text("无需账号")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.requiredAccounts, id: \.self) { accountId in
                    AccountStatusRow(
                        accountId: accountId,
                        isLoggedIn: viewModel.loggedInAccounts.contains(accountId),
                        isExpired: viewModel.expiredAccounts.contains(accountId)
                    )
                }
            }

            // 未登录提示
            if !viewModel.expiredAccounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .foregroundColor(.red)
                        Text("以下账号未登录或已过期：")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    Text(viewModel.expiredAccounts.sorted().joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("请先前往「账号管理」完成登录，再开始执行")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }
                .padding(10)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - 操作按钮

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 10) {
            // 开始执行按钮（所有账号登录后才可点击）
            Button {
                viewModel.startExecution()
            } label: {
                Label(
                    viewModel.canStartExecution ? "开始执行" : "账号未全部登录",
                    systemImage: "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canStartExecution)

            // 取消按钮
            Button("取消") {
                viewModel.reset()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .controlSize(.regular)
        }
    }
}

// MARK: - 统计数字徽章

/// 彩色统计数字卡片
private struct StatBadge: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - 账号登录状态行

/// 单个账号的登录状态展示行
private struct AccountStatusRow: View {
    let accountId: String
    let isLoggedIn: Bool
    let isExpired: Bool

    var body: some View {
        HStack(spacing: 8) {
            // 状态图标
            Image(systemName: isLoggedIn ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isLoggedIn ? .green : .red)
                .font(.body)

            // 账号 ID
            Text(accountId)
                .font(.callout)
                .lineLimit(1)

            Spacer()

            // 状态文字
            Text(isLoggedIn ? "已登录" : "未登录")
                .font(.caption)
                .foregroundColor(isLoggedIn ? .green : .red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((isLoggedIn ? Color.green : Color.red).opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }
}
