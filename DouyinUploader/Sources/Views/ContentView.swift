import SwiftUI

/// 侧边栏导航项
enum SidebarItem: String, CaseIterable, Identifiable {
    case feishuConfig = "飞书配置"
    case accountManage = "账号管理"
    case execution = "执行发布"
    case history = "历史记录"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .feishuConfig: return "tablecells"
        case .accountManage: return "person.2"
        case .execution: return "play.circle"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .execution
    @State private var showOnboarding: Bool = false

    @EnvironmentObject private var settingsManagerStore: SettingsManagerStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @StateObject private var accountViewModel = AccountViewModel()

    var body: some View {
        VStack(spacing: 0) {
            NavigationView {
                SidebarView(selection: $selectedItem)
                detailView
            }

            StatusBarView()
                .environmentObject(accountViewModel)
        }
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .environmentObject(settingsManagerStore)
        }
        .onAppear {
            if !settingsManagerStore.settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: settingsManagerStore.settings.hasCompletedOnboarding) { completed in
            if !completed {
                showOnboarding = true
            }
        }
        .environmentObject(accountViewModel)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .feishuConfig:
            FeishuConfigListView()
        case .accountManage:
            AccountListView()
        case .execution:
            ExecutionView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        case nil:
            Text("请选择一个页面")
                .foregroundColor(.secondary)
        }
    }
}

/// 占位 View — 后续逐步替换为真实页面
struct PlaceholderView: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(title)
                .font(.title2)
                .foregroundColor(.secondary)
            Text("开发中...")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
