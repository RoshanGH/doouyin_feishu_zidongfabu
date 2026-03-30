import SwiftUI

/// 执行完成总结视图
/// 展示：总任务数、成功、失败、耗时；失败明细；操作按钮
struct SummaryView: View {
    @ObservedObject var viewModel: ExecutionViewModel

    var body: some View {
        HSplitView {
            // 左侧：总结面板
            summaryPanel
                .frame(minWidth: 260, idealWidth: 300)

            // 右侧：完整日志
            if !viewModel.logs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("执行日志")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                        Spacer()
                    }
                    Divider()
                    LogScrollView(logs: viewModel.logs)
                }
                .frame(minWidth: 400)
            }
        }
    }

    // MARK: - 左侧总结面板

    @ViewBuilder
    private var summaryPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // 图标 + 标题
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: summaryIcon)
                        .font(.system(size: 36))
                        .foregroundColor(summaryIconColor)

                    Text(summaryTitle)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(summarySubtitle)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)

                Divider()

                // 统计卡片
                statsSection

                Divider()

                // 失败明细（如果有）
                if viewModel.failedCount > 0 {
                    failedDetailSection
                    Divider()
                }

                // 操作按钮
                actionButtons

                Spacer(minLength: 16)
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 统计区块

    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("执行结果")
                .font(.headline)

            // 四格统计
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SummaryStatCard(
                    value: viewModel.validTasks.count,
                    label: "总任务",
                    color: .primary,
                    icon: "list.bullet"
                )
                SummaryStatCard(
                    value: viewModel.successCount,
                    label: "成功",
                    color: .green,
                    icon: "checkmark.circle.fill"
                )
                SummaryStatCard(
                    value: viewModel.failedCount,
                    label: "失败",
                    color: .red,
                    icon: "xmark.circle.fill"
                )
                SummaryStatCard(
                    value: viewModel.invalidTasks.count,
                    label: "已跳过",
                    color: .orange,
                    icon: "exclamationmark.triangle.fill"
                )
            }

            // 耗时
            if let log = viewModel.executionLog {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("耗时：\(log.durationFormatted)")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - 失败明细

    @ViewBuilder
    private var failedDetailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("失败明细")
                .font(.headline)

            // 从日志中提取 error 级别的条目
            let errorLogs = viewModel.logs.filter { $0.level == .error }
            if errorLogs.isEmpty {
                Text("无详细信息")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ForEach(errorLogs.prefix(10)) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 2) {
                            if let account = entry.account {
                                let nickname = viewModel.accountNicknames[account]
                                Text(nickname ?? account)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            Text(entry.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.06))
                    .cornerRadius(6)
                }

                if errorLogs.count > 10 {
                    Text("还有 \(errorLogs.count - 10) 条错误，请查看完整日志")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 操作按钮

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 10) {
            // 重新执行失败项（仅在有失败时显示）
            if viewModel.failedCount > 0 {
                Button {
                    viewModel.retryFailedTasks()
                } label: {
                    Label("重新执行失败项", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
            }

            // 重新开始（全部重新读取执行）
            Button {
                viewModel.reset()
                viewModel.loadConfigs()
            } label: {
                Label("重新开始", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // 关闭
            Button {
                viewModel.reset()
            } label: {
                Text("关闭")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - 辅助计算属性

    private var isAllSuccess: Bool {
        viewModel.failedCount == 0 && viewModel.successCount > 0
    }

    private var summaryIcon: String {
        if isAllSuccess { return "checkmark.seal.fill" }
        if viewModel.successCount == 0 { return "xmark.seal.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var summaryIconColor: Color {
        if isAllSuccess { return .green }
        if viewModel.successCount == 0 { return .red }
        return .orange
    }

    private var summaryTitle: String {
        if isAllSuccess { return "全部发布成功！" }
        if viewModel.successCount == 0 { return "发布全部失败" }
        return "部分发布成功"
    }

    private var summarySubtitle: String {
        let total = viewModel.validTasks.count
        let success = viewModel.successCount
        let failed = viewModel.failedCount
        return "共执行 \(total) 条任务，成功 \(success) 条，失败 \(failed) 条"
    }
}

// MARK: - 统计卡片

private struct SummaryStatCard: View {
    let value: Int
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }
}
