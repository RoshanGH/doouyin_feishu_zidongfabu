import Foundation

/// Chrome for Testing 下载和生命周期管理
/// 首次运行自动下载 Chromium 到 Application Support，后续直接使用
final class ChromeManager {

    // MARK: - 路径

    static let shared = ChromeManager()

    private let appSupportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("com.menggang.douyin-uploader", isDirectory: true)
    }()

    /// Chrome 安装目录
    var chromeDir: URL { appSupportDir.appendingPathComponent("chrome", isDirectory: true) }

    /// Chrome 可执行文件路径
    var chromeExecutable: URL {
        let arch = ProcessInfo.processInfo.machineArchitecture
        let platform = arch == "arm64" ? "chrome-mac-arm64" : "chrome-mac-x64"
        return chromeDir
            .appendingPathComponent(platform)
            .appendingPathComponent("Google Chrome for Testing.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("Google Chrome for Testing")
    }

    /// 用户数据目录（按账号隔离）
    func userDataDir(for accountId: String) -> URL {
        appSupportDir
            .appendingPathComponent("chrome-profiles", isDirectory: true)
            .appendingPathComponent(accountId, isDirectory: true)
    }

    /// Chrome 是否已安装
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: chromeExecutable.path)
    }

    // MARK: - 下载

    /// 下载进度回调
    var onDownloadProgress: ((Double, String) -> Void)?

    /// Chrome for Testing 版本号（固定一个稳定版本）
    private let chromeVersion = "131.0.6778.204"

    /// 下载并安装 Chrome for Testing
    func downloadIfNeeded() async throws {
        if isInstalled {
            onDownloadProgress?(1.0, "Chrome 已就绪")
            return
        }

        let arch = ProcessInfo.processInfo.machineArchitecture
        let platform = arch == "arm64" ? "mac-arm64" : "mac-x64"
        let downloadURL = "https://storage.googleapis.com/chrome-for-testing-public/\(chromeVersion)/\(platform)/chrome-\(platform).zip"

        onDownloadProgress?(0.0, "正在下载 Chrome (\(platform))...")

        guard let url = URL(string: downloadURL) else {
            throw ChromeError.invalidURL(downloadURL)
        }

        // 创建目录
        try FileManager.default.createDirectory(at: chromeDir, withIntermediateDirectories: true)

        // 下载 zip
        let zipURL = chromeDir.appendingPathComponent("chrome.zip")
        let (tempURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ChromeError.downloadFailed("HTTP 状态码异常")
        }

        // 移动下载文件
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: zipURL)

        onDownloadProgress?(0.7, "正在解压...")

        // 解压
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-o", zipURL.path, "-d", chromeDir.path]
        unzipProcess.standardOutput = FileHandle.nullDevice
        unzipProcess.standardError = FileHandle.nullDevice
        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        if unzipProcess.terminationStatus != 0 {
            throw ChromeError.unzipFailed
        }

        // 清理 zip
        try? FileManager.default.removeItem(at: zipURL)

        // 设置可执行权限
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: chromeExecutable.path
        )

        // 移除 quarantine 属性（避免 macOS Gatekeeper 阻止）
        let xattrProcess = Process()
        xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProcess.arguments = ["-cr", chromeDir.path]
        xattrProcess.standardOutput = FileHandle.nullDevice
        xattrProcess.standardError = FileHandle.nullDevice
        try? xattrProcess.run()
        xattrProcess.waitUntilExit()

        onDownloadProgress?(1.0, "Chrome 安装完成")
    }

    // MARK: - 启动 Chrome 进程

    /// 启动一个 Chrome 实例
    /// - Parameters:
    ///   - accountId: 账号 ID（隔离用户数据）
    ///   - port: 调试端口
    ///   - headless: 是否无头模式
    /// - Returns: (Process, WebSocket URL)
    func launchChrome(accountId: String, port: Int = 0, headless: Bool = true) async throws -> (Process, Int) {
        guard isInstalled else {
            throw ChromeError.notInstalled
        }

        // 自动选择可用端口
        let debugPort = port > 0 ? port : findAvailablePort()

        // 先杀掉旧的 Chrome 进程（避免端口冲突）
        killAllChromeProcesses()
        try await Task.sleep(nanoseconds: 500_000_000)

        let profileDir = userDataDir(for: accountId)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = chromeExecutable
        var args = [
            "--remote-debugging-port=\(debugPort)",
            "--user-data-dir=\(profileDir.path)",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-extensions",
            "--disable-background-networking",
            "--disable-sync",
            "--disable-translate",
            "--disable-blink-features=AutomationControlled",
            "--window-size=1280,800"
        ]

        if headless {
            args.append("--headless=new")
        }

        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()

        // 等待 Chrome 启动（最多 20 秒）
        for i in 0..<40 {
            try await Task.sleep(nanoseconds: 500_000_000)
            if let _ = try? await getWebSocketURL(port: debugPort) {
                print("[Chrome] 启动成功，耗时约 \(Double(i) * 0.5)s，端口 \(debugPort)")
                return (process, debugPort)
            }
        }

        process.terminate()
        throw ChromeError.launchTimeout
    }

    /// 获取 CDP WebSocket URL
    func getWebSocketURL(port: Int) async throws -> String {
        let url = URL(string: "http://127.0.0.1:\(port)/json/version")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wsURL = json["webSocketDebuggerUrl"] as? String else {
            throw ChromeError.invalidCDPResponse
        }
        return wsURL
    }

    /// 获取页面列表中第一个页面的 WebSocket URL
    func getPageWebSocketURL(port: Int) async throws -> String {
        let url = URL(string: "http://127.0.0.1:\(port)/json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let pages = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let firstPage = pages.first,
              let wsURL = firstPage["webSocketDebuggerUrl"] as? String else {
            throw ChromeError.invalidCDPResponse
        }
        return wsURL
    }

    // MARK: - 工具

    /// 杀掉所有 Chrome for Testing 进程
    func killAllChromeProcesses() {
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProcess.arguments = ["-f", "Chrome for Testing"]
        killProcess.standardOutput = FileHandle.nullDevice
        killProcess.standardError = FileHandle.nullDevice
        try? killProcess.run()
        killProcess.waitUntilExit()
    }

    private func findAvailablePort() -> Int {
        return 9222
    }
}

// MARK: - 错误

enum ChromeError: LocalizedError {
    case notInstalled
    case invalidURL(String)
    case downloadFailed(String)
    case unzipFailed
    case launchTimeout
    case invalidCDPResponse

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Chrome 未安装，请先在设置中下载"
        case .invalidURL(let url): return "无效的下载 URL: \(url)"
        case .downloadFailed(let msg): return "Chrome 下载失败: \(msg)"
        case .unzipFailed: return "Chrome 解压失败"
        case .launchTimeout: return "Chrome 启动超时"
        case .invalidCDPResponse: return "无法获取 Chrome 调试信息"
        }
    }
}

// MARK: - 获取 CPU 架构

extension ProcessInfo {
    var machineArchitecture: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }
}
