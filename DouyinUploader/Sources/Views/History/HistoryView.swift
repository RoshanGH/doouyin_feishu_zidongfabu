import SwiftUI

/// 历史记录页面
struct HistoryView: View {

    @StateObject private var viewModel = HistoryViewModel()
    @State private var showExportPanel: Bool = false

    var body: some View {
        HSplitView {
            historyListPanel
            logDetailPanel
        }
        .onAppear {
            viewModel.loadHistory()
        }
        .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.exportURL) { url in
            if url != nil {
                showExportPanel = true
            }
        }
        .sheet(isPresented: $showExportPanel) {
            if let url = viewModel.exportURL {
                ExportSavePanel(sourceURL: url) {
                    viewModel.exportURL = nil
                    showExportPanel = false
                }
            }
        }
    }

    // MARK: - 左侧列表

    private var historyListPanel: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("历史记录")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.loadHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("刷新")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if viewModel.isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.historyList.isEmpty {
                emptyState
            } else {
                List(viewModel.historyList, selection: Binding(
                    get: { viewModel.selectedLog?.id },
                    set: { id in
                        if let id { viewModel.selectLog(id: id) }
                        else { viewModel.clearSelection() }
                    }
                )) { log in
                    HistoryRowView(log: log)
                        .contextMenu {
                            Button("导出日志") { viewModel.exportLog(id: log.id) }
                            Divider()
                            Button("删除", role: .destructive) { viewModel.deleteLog(id: log.id) }
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 260, maxWidth: 320)
    }

    // MARK: - 右侧详情

    private var logDetailPanel: some View {
        Group {
            if let log = viewModel.selectedLog {
                LogDetailView(log: log) {
                    viewModel.exportLog(id: log.id)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("选择一条记录查看详情")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("暂无执行记录")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("执行完成后，日志将自动保存于此")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - 历史列表行

struct HistoryRowView: View {
    let log: ExecutionLog

    private var statusColor: Color {
        if log.failedCount == 0 { return .green }
        if log.successCount == 0 { return .red }
        return .orange
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: log.startedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.feishuConfigName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(dateText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text("成功 \(log.successCount)")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("失败 \(log.failedCount)")
                    .font(.caption)
                    .foregroundColor(.red)
                Spacer()
                Text(log.durationFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 日志详情

struct LogDetailView: View {
    let log: ExecutionLog
    let onExport: () -> Void

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: log.startedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部信息栏
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.feishuConfigName)
                        .font(.headline)
                    Text(dateText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Label("\(log.successCount)", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Label("\(log.failedCount)", systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                Label(log.durationFormatted, systemImage: "clock")
                    .foregroundColor(.secondary)
                Button("导出日志") {
                    onExport()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 日志内容
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if log.entries.isEmpty {
                        Text("（无详细日志条目）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(log.entries) { entry in
                            LogEntryRowView(entry: entry)
                        }
                    }
                }
                .padding(8)
            }
        }
    }
}

// MARK: - 单条日志条目

struct LogEntryRowView: View {
    let entry: LogEntry

    private var levelColor: Color {
        switch entry.level {
        case .info: return .primary
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        }
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: entry.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(timeText)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Text("[\(entry.level.rawValue.uppercased())]")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(levelColor)
                .frame(width: 70, alignment: .leading)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(levelColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }
}

// MARK: - 导出面板包装

/// 使用 NSSavePanel 让用户选择保存位置
struct ExportSavePanel: View {
    let sourceURL: URL
    let onDismiss: () -> Void

    var body: some View {
        // SwiftUI sheet 包装 NSSavePanel，展示后立即弹出原生面板
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                showSavePanel()
            }
    }

    private func showSavePanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.allowedContentTypes = [.plainText]
        panel.title = "导出日志"

        panel.begin { response in
            if response == .OK, let dst = panel.url {
                try? FileManager.default.copyItem(at: sourceURL, to: dst)
            }
            onDismiss()
        }
    }
}
