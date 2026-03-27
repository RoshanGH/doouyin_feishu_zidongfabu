import Foundation
import Network

/// 网络状态监控
/// 使用 NWPathMonitor 实时监测网络连通性
final class NetworkMonitor: ObservableObject {

    @Published private(set) var isConnected: Bool = true

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.menggang.douyin-uploader.network", qos: .utility)
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }
}
