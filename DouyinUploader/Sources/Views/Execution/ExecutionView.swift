import SwiftUI

/// 执行发布主容器 View
/// 根据 ExecutionViewModel.state 切换不同子视图
struct ExecutionView: View {

    @StateObject private var viewModel = ExecutionViewModel()

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                ExecutionIdleView(viewModel: viewModel)
            case .loading:
                ExecutionLoadingView()
            case .loadFailed(let msg):
                ExecutionErrorView(message: msg, viewModel: viewModel)
            case .noTasks:
                ExecutionNoTasksView(viewModel: viewModel)
            case .overview:
                ExecutionOverviewContainer(viewModel: viewModel)
            case .running:
                ExecutionProgressView(viewModel: viewModel)
            case .paused:
                ExecutionProgressView(viewModel: viewModel)
            case .networkError:
                ExecutionNetworkErrorView(viewModel: viewModel)
            case .completed:
                SummaryView(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.loadConfigs()
        }
    }
}

// MARK: - 空闲状态：选择配置并拉取任务

/// 初始状态视图 — 选择飞书配置，点击拉取任务
struct ExecutionIdleView: View {
    @ObservedObject var viewModel: ExecutionViewModel

    var body: some View {
        VStack(spacing: 24) {
            // 标题区
            VStack(spacing: 8) {
                Image(systemName: "play.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                Text("执行发布")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("选择飞书配置后，读取待发布任务并开始执行")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(width: 300)

            // 配置选择
            VStack(alignment: .leading, spacing: 8) {
                Text("飞书配置")
                    .font(.headline)

                if viewModel.configs.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("暂无飞书配置，请先在「飞书配置」中添加")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .frame(width: 360)
                } else {
                    Picker("选择配置", selection: $viewModel.selectedConfigId) {
                        Text("请选择配置").tag(nil as UUID?)
                        ForEach(viewModel.configs) { config in
                            Text(config.name).tag(config.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 360)
                }
            }

            // 读取按钮
            Button {
                Task {
                    await viewModel.loadTasks()
                }
            } label: {
                Label("读取任务", systemImage: "arrow.clockwise")
                    .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedConfigId == nil || viewModel.configs.isEmpty)
            .controlSize(.large)
        }
        .padding(40)
    }
}

// MARK: - 加载中状态

/// 正在读取飞书任务的加载动画视图
struct ExecutionLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在读取飞书任务...")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 读取失败状态

/// 读取任务失败的错误提示视图
struct ExecutionErrorView: View {
    let message: String
    @ObservedObject var viewModel: ExecutionViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("读取任务失败")
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 12) {
                Button("返回") {
                    viewModel.reset()
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await viewModel.loadTasks()
                    }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
    }
}

// MARK: - 无任务状态

/// 没有待执行任务的提示视图
struct ExecutionNoTasksView: View {
    @ObservedObject var viewModel: ExecutionViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("暂无待发布任务")
                .font(.title3)
                .fontWeight(.semibold)

            Text("飞书表格中没有状态为「允许发布」、「发布失败」或「发布中」的记录")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("返回") {
                viewModel.reset()
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
    }
}

// MARK: - 概览容器（任务预览 + 账号状态）

/// 任务概览容器：左边账号状态 + 右边任务预览列表
struct ExecutionOverviewContainer: View {
    @ObservedObject var viewModel: ExecutionViewModel

    var body: some View {
        HSplitView {
            // 左侧：概览面板
            TaskOverviewView(viewModel: viewModel)
                .frame(minWidth: 260, idealWidth: 300)

            // 右侧：任务预览列表
            TaskPreviewView(viewModel: viewModel)
                .frame(minWidth: 400)
        }
    }
}

// MARK: - 网络错误状态

/// 执行中网络错误视图（可重试）
struct ExecutionNetworkErrorView: View {
    @ObservedObject var viewModel: ExecutionViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("网络连接异常")
                .font(.title3)
                .fontWeight(.semibold)

            Text("执行过程中发生网络错误，请检查网络连接后重试")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 12) {
                Button("停止执行") {
                    viewModel.stopExecution()
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.resumeExecution()
                } label: {
                    Label("继续执行", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
    }
}
