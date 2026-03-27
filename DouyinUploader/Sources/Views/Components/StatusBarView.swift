import SwiftUI

/// 底部状态栏
/// 显示：网络状态、已登录账号数、上次执行时间/正在执行进度
struct StatusBarView: View {

    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var accountViewModel: AccountViewModel

    /// 外部传入执行状态
    var isExecuting: Bool = false
    var executionProgress: String? = nil
    var lastExecutionTime: Date? = nil

    var body: some View {
        HStack(spacing: 16) {
            // 网络状态
            networkStatusView

            Divider()
                .frame(height: 12)

            // 已登录账号数
            accountCountView

            Divider()
                .frame(height: 12)

            // 执行状态
            executionStatusView

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    // MARK: - 网络状态

    private var networkStatusView: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(networkMonitor.isConnected ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(networkMonitor.isConnected ? "网络正常" : "网络断开")
        }
    }

    // MARK: - 账号数

    private var accountCountView: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2")
            Text("账号：\(accountViewModel.accounts.count)")
        }
    }

    // MARK: - 执行状态

    private var executionStatusView: some View {
        Group {
            if isExecuting {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                    Text(executionProgress ?? "正在执行...")
                }
            } else if let lastTime = lastExecutionTime {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("上次执行：\(relativeTimeText(lastTime))")
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("尚未执行")
                }
            }
        }
    }

    // MARK: - 相对时间

    private func relativeTimeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
