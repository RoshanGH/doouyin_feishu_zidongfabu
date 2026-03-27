import SwiftUI

/// 任务预览列表 View
/// 以卡片形式展示所有任务（有效 + 无效），校验失败的任务用红色标注
struct TaskPreviewView: View {
    @ObservedObject var viewModel: ExecutionViewModel

    /// 是否折叠无效任务区块
    @State private var invalidCollapsed = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {

                // 标题栏
                HStack {
                    Text("任务预览")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    Text("共 \(viewModel.tasks.count) 条")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)

                // 有效任务列表
                if !viewModel.validTasks.isEmpty {
                    SectionHeader(
                        title: "有效任务（\(viewModel.validTasks.count)）",
                        color: .blue
                    )

                    ForEach(Array(viewModel.validTasks.enumerated()), id: \.element.id) { index, task in
                        TaskCard(
                            index: index + 1,
                            task: task,
                            isInvalid: false
                        )
                    }
                }

                // 无效任务列表（可折叠）
                if !viewModel.invalidTasks.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            invalidCollapsed.toggle()
                        }
                    } label: {
                        HStack {
                            SectionHeader(
                                title: "无效任务（\(viewModel.invalidTasks.count)）- 将跳过",
                                color: .red
                            )
                            Spacer()
                            Image(systemName: invalidCollapsed ? "chevron.down" : "chevron.up")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if !invalidCollapsed {
                        ForEach(Array(viewModel.invalidTasks.enumerated()), id: \.element.id) { index, task in
                            TaskCard(
                                index: index + 1,
                                task: task,
                                isInvalid: true
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - 分组标题

private struct SectionHeader: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 3, height: 16)
                .cornerRadius(2)

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 任务卡片

/// 单条任务的卡片展示
private struct TaskCard: View {
    let index: Int
    let task: PublishTask
    let isInvalid: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶部行：序号 + 账号 + 类型标签 + 状态
            HStack(spacing: 8) {
                // 序号
                Text("\(index)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(isInvalid ? Color.red : Color.accentColor)
                    .clipShape(Circle())

                // 抖音号
                Text(task.displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if task.douyinName != nil {
                    Text(task.douyinAccountId)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 类型标签
                TypeBadge(isVideo: task.isVideo, isInvalid: isInvalid)

                // 状态标签
                if isInvalid {
                    StatusBadge(text: "跳过", color: .red)
                } else {
                    StatusBadge(text: task.status.rawValue, color: statusColor(task.status))
                }
            }

            // 文案摘要（最多 2 行）
            if !task.content.isEmpty {
                Text(task.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // 话题标签
            if !task.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(task.tags, id: \.self) { tag in
                            Text(tag.hasPrefix("#") ? tag : "#\(tag)")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            // 音乐名称
            if task.hasMusic {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundColor(.pink)
                    Text(task.musicName ?? "")
                        .font(.caption2)
                        .foregroundColor(.pink)
                }
            }

            // 校验失败原因
            if isInvalid {
                let reason = task.failureReason ?? invalidReason(task)
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            // 定时发布信息
            if let scheduledTime = task.scheduledTime {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("定时：\(formatDate(scheduledTime))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isInvalid ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        )
    }

    private func invalidReason(_ task: PublishTask) -> String {
        switch task.mediaValidation {
        case .invalid(let reason): return reason
        default: return "校验失败"
        }
    }

    private func statusColor(_ status: PublishStatus) -> Color {
        switch status {
        case .allowPublish: return .blue
        case .publishing: return .orange
        case .published: return .green
        case .publishFailed: return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - 类型徽章

private struct TypeBadge: View {
    let isVideo: Bool
    let isInvalid: Bool

    var body: some View {
        let label = isInvalid ? "未知" : (isVideo ? "视频" : "图文")
        let color: Color = isInvalid ? .gray : (isVideo ? .blue : .purple)

        Text(label)
            .font(.caption2)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(4)
    }
}

// MARK: - 状态徽章

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(4)
    }
}
