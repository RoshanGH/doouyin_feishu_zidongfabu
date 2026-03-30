import Foundation
import UserNotifications

/// 系统通知服务
final class NotificationService {

    static let shared = NotificationService()

    private init() {}

    /// Bundle 是否有效（SPM executableTarget 在 Xcode debug 时可能无有效 Bundle）
    private var canUseNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// 请求通知权限
    func requestPermission() {
        guard canUseNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    /// 发送执行完成通知
    func sendExecutionComplete(success: Int, failed: Int) {
        guard canUseNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = "抖音上传完成"
        content.body = "成功 \(success) 条，失败 \(failed) 条"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
