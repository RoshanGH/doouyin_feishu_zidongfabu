import SwiftUI

/// 执行进度 + 实时日志视图
/// 运行中（running）和暂停中（paused）都使用此视图
struct ExecutionProgressView: View {
    @ObservedObject var viewModel: ExecutionViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 顶部进度区
            progressHeader
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 日志区域（自动滚动）
            LogScrollView(logs: viewModel.logs)

            Divider()

            // 底部统计 + 操作按钮
            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    // MARK: - 顶部进度区

    @ViewBuilder
    private var progressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                // 状态标题
                HStack(spacing: 8) {
                    if case .paused = viewModel.state {
                        Image(systemName: "pause.circle.fill")
                            .foregroundColor(.orange)
                    } else {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(statusTitle)
                        .font(.headline)
                }

                Spacer()

                // 当前进度
                Text("\(completedCount) / \(viewModel.validTasks.count)")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            // 进度条
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .accentColor(progressColor)

                HStack {
                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let startTime = viewModel.startTime {
                        ElapsedTimeText(startTime: startTime)
                    }
                }
            }
        }
    }

    // MARK: - 底部统计 + 操作按钮

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 20) {
            // 统计数字
            HStack(spacing: 16) {
                StatItem(value: viewModel.successCount, label: "成功", color: .green)
                StatItem(value: viewModel.failedCount, label: "失败", color: .red)
                StatItem(value: viewModel.remainingCount, label: "剩余", color: .secondary)
            }

            Spacer()

            // 操作按钮
            HStack(spacing: 10) {
                if case .running = viewModel.state {
                    // 运行中：显示暂停
                    Button {
                        viewModel.pauseExecution()
                    } label: {
                        Label("暂停", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)

                } else if case .paused = viewModel.state {
                    // 暂停中：显示继续
                    Button {
                        viewModel.resumeExecution()
                    } label: {
                        Label("继续", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // 停止按钮
                Button {
                    viewModel.stopExecution()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
    }

    // MARK: - 辅助计算属性

    private var statusTitle: String {
        switch viewModel.state {
        case .paused: return "执行已暂停"
        case .running:
            if viewModel.currentTaskIndex < viewModel.validTasks.count {
                let task = viewModel.validTasks[viewModel.currentTaskIndex]
                let nickname = viewModel.accountNicknames[task.douyinAccountId] ?? task.douyinAccountId
                // 显示最后一条日志作为当前步骤
                if let lastLog = viewModel.logs.last, lastLog.level == .info {
                    return "[\(nickname)] \(lastLog.message)"
                }
                return "正在发布：\(nickname)"
            }
            return "正在执行..."
        default: return "正在执行..."
        }
    }

    private var progressColor: Color {
        if case .paused = viewModel.state { return .orange }
        return .accentColor
    }

    private var completedCount: Int {
        viewModel.successCount + viewModel.failedCount
    }

    private func elapsedTime(since startTime: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(startTime))
        let minutes = elapsed / 60
        let secs = elapsed % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - 日志滚动区域

/// 实时日志滚动列表，新日志追加时自动滚动到底部
struct LogScrollView: View {
    let logs: [LogEntry]
    @State private var filterLevel: LogLevel? = nil

    private var filteredLogs: [LogEntry] {
        guard let level = filterLevel else { return logs }
        return logs.filter { $0.level == level }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 过滤栏
            HStack(spacing: 8) {
                FilterButton(label: "全部", isActive: filterLevel == nil) { filterLevel = nil }
                FilterButton(label: "错误", isActive: filterLevel == .error, color: .red) { filterLevel = .error }
                FilterButton(label: "警告", isActive: filterLevel == .warning, color: .orange) { filterLevel = .warning }
                FilterButton(label: "成功", isActive: filterLevel == .success, color: .green) { filterLevel = .success }
                Spacer()
                Text("\(filteredLogs.count) 条")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredLogs) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            // 当 logs 数组变化时，自动滚动到最新一条
            .onChange(of: logs.count) { _ in
                if let lastId = logs.last?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
        } // VStack
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - 日志过滤按钮

private struct FilterButton: View {
    let label: String
    let isActive: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? color.opacity(0.15) : Color.clear)
                .foregroundColor(isActive ? color : .secondary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 日志条目行

/// 单条日志的展示行（等宽字体 + 颜色编码）
private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 时间戳
            Text(formatTime(entry.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 68, alignment: .leading)

            // 级别图标
            Text(levelIcon(entry.level))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(levelColor(entry.level))
                .frame(width: 8)

            // 消息内容
            Text(entry.message)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(levelColor(entry.level))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func levelIcon(_ level: LogLevel) -> String {
        switch level {
        case .info:    return "·"
        case .success: return "✓"
        case .error:   return "✗"
        case .warning: return "!"
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .info:    return .primary
        case .success: return .green
        case .error:   return .red
        case .warning: return .orange
        }
    }
}

// MARK: - 底部统计项

private struct StatItem: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 耗时实时刷新

/// 每秒刷新一次的耗时文本（兼容 macOS 12）
private struct ElapsedTimeText: View {
    let startTime: Date
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text("耗时：\(formatted)")
            .font(.caption)
            .foregroundColor(.secondary)
            .onReceive(timer) { now = $0 }
    }

    private var formatted: String {
        let elapsed = Int(now.timeIntervalSince(startTime))
        let minutes = elapsed / 60
        let secs = elapsed % 60
        return minutes > 0 ? "\(minutes)m\(secs)s" : "\(secs)s"
    }
}
