import SwiftUI

/// 设置页面
struct SettingsView: View {

    @EnvironmentObject private var settingsManager: SettingsManagerStore

    @State private var chromeInstalled = ChromeManager.shared.isInstalled
    @State private var isDownloading = false
    @State private var downloadStatus = ""

    var body: some View {
        if #available(macOS 13.0, *) {
            Form {
                chromeSection
                executionSection
                systemSection
                advancedSection
                otherSection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // macOS 12: 没有 .formStyle(.grouped)，用 ScrollView + VStack 模拟
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    settingsGroup("浏览器引擎") { chromeSection }
                    settingsGroup("执行参数") { executionSection }
                    settingsGroup("系统") { systemSection }
                    settingsGroup("高级") { advancedSection }
                    settingsGroup("其他") { otherSection }
                    settingsGroup("关于") { aboutSection }
                }
                .frame(maxWidth: 600)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("设置")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    // MARK: - 浏览器引擎

    private var chromeSection: some View {
        Section("浏览器引擎") {
            HStack {
                if chromeInstalled {
                    Label("Chrome 已就绪", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("Chrome 未安装", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                Spacer()
                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(downloadStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if !chromeInstalled {
                    Button("下载安装") {
                        downloadChrome()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            Text("发布功能需要内置浏览器引擎，首次使用需下载约 130MB")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func downloadChrome() {
        isDownloading = true
        downloadStatus = "准备下载..."

        ChromeManager.shared.onDownloadProgress = { progress, status in
            DispatchQueue.main.async {
                self.downloadStatus = status
            }
        }

        Task {
            do {
                try await ChromeManager.shared.downloadIfNeeded()
                await MainActor.run {
                    chromeInstalled = true
                    isDownloading = false
                    downloadStatus = ""
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadStatus = "下载失败: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 执行参数

    private var executionSection: some View {
        Section("执行参数") {
            VStack(alignment: .leading, spacing: 2) {
                Text("任务间隔（秒）")
                    .font(.callout)
                HStack {
                    Text("最小")
                        .foregroundColor(.secondary)
                        .frame(width: 36)
                    Stepper(
                        value: $settingsManager.settings.taskIntervalMin,
                        in: 1...60,
                        step: 1
                    ) {
                        Text(String(format: "%.0f 秒", settingsManager.settings.taskIntervalMin))
                            .frame(width: 50)
                    }
                    Text("最大")
                        .foregroundColor(.secondary)
                        .frame(width: 36)
                    Stepper(
                        value: $settingsManager.settings.taskIntervalMax,
                        in: 1...120,
                        step: 1
                    ) {
                        Text(String(format: "%.0f 秒", settingsManager.settings.taskIntervalMax))
                            .frame(width: 50)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("JS 操作延迟（秒）")
                    .font(.callout)
                HStack {
                    Text("最小")
                        .foregroundColor(.secondary)
                        .frame(width: 36)
                    Stepper(
                        value: $settingsManager.settings.jsDelayMin,
                        in: 0.1...5,
                        step: 0.1
                    ) {
                        Text(String(format: "%.1f 秒", settingsManager.settings.jsDelayMin))
                            .frame(width: 50)
                    }
                    Text("最大")
                        .foregroundColor(.secondary)
                        .frame(width: 36)
                    Stepper(
                        value: $settingsManager.settings.jsDelayMax,
                        in: 0.1...10,
                        step: 0.1
                    ) {
                        Text(String(format: "%.1f 秒", settingsManager.settings.jsDelayMax))
                            .frame(width: 50)
                    }
                }
            }

            HStack {
                Text("单账号批量上限")
                Spacer()
                Stepper(
                    value: $settingsManager.settings.batchLimit,
                    in: 1...100
                ) {
                    Text("\(settingsManager.settings.batchLimit) 条")
                        .frame(width: 55, alignment: .trailing)
                }
            }

            HStack {
                Text("达到上限后等待")
                Spacer()
                Stepper(
                    value: $settingsManager.settings.batchWaitMinutes,
                    in: 1...60
                ) {
                    Text("\(settingsManager.settings.batchWaitMinutes) 分钟")
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - 系统

    private var systemSection: some View {
        Section("系统") {
            Toggle("执行完成后发送通知", isOn: $settingsManager.settings.enableNotification)
            Toggle("执行期间防止休眠", isOn: $settingsManager.settings.preventSleep)

            HStack {
                Text("日志保留天数")
                Spacer()
                Stepper(
                    value: $settingsManager.settings.logRetentionDays,
                    in: 1...365
                ) {
                    Text("\(settingsManager.settings.logRetentionDays) 天")
                        .frame(width: 55, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - 高级

    private var advancedSection: some View {
        Section("高级") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("调试模式", isOn: $settingsManager.settings.debugMode)
                Text("开启后执行发布时会显示浏览器窗口，可实时观察发布过程和排查问题")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("编辑选择器 JSON") {
                openSelectorsFile()
            }
            .help("在默认编辑器中打开 selectors.json（位于 Application Support）")
        }
    }

    // MARK: - 其他

    private var otherSection: some View {
        Section("其他") {
            Button("重新显示引导") {
                settingsManager.settings.hasCompletedOnboarding = false
                settingsManager.saveSettings()
            }
            .foregroundColor(.accentColor)
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("作者联系方式")
                Spacer()
                Text("微信：13462890087")
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Text("版本")
                Spacer()
                Text("v1.2.1")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 打开选择器文件

    private func openSelectorsFile() {
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fallback
        let selectorsURL = appSupport
            .appendingPathComponent("com.menggang.douyin-uploader", isDirectory: true)
            .appendingPathComponent("selectors.json")

        // 如果文件不存在，先从 Bundle 复制一份
        if !FileManager.default.fileExists(atPath: selectorsURL.path) {
            if let bundleURL = Bundle.main.url(forResource: "selectors", withExtension: "json") {
                try? FileManager.default.createDirectory(
                    at: selectorsURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.copyItem(at: bundleURL, to: selectorsURL)
            }
        }

        NSWorkspace.shared.open(selectorsURL)
    }

    /// macOS 12 兼容：手动渲染分组标题 + 内容（替代 Form + .formStyle(.grouped)）
    @ViewBuilder
    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}
