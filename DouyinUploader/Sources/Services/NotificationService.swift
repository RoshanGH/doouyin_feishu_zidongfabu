import Foundation
import UserNotifications

/// 系统通知服务
final class NotificationService {

    static let shared = NotificationService()

    private init() {}

    /// 请求通知权限
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in
            // 静默处理权限结果，用户可在系统设置中更改
        }
    }

    /// 发送执行完成通知
    /// - Parameters:
    ///   - success: 成功数量
    ///   - failed: 失败数量
    func sendExecutionComplete(success: Int, failed: Int) {
        let content = UNMutableNotificationContent()
        content.title = "抖音上传完成"
        content.body = "成功 \(success) 条，失败 \(failed) 条"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // 立即发送
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                // 通知发送失败不阻断主流程，仅记录
                print("[NotificationService] 发送通知失败：\(error.localizedDescription)")
            }
        }
    }
}
