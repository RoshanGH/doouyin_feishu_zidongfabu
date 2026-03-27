import Foundation
import SwiftUI

/// 可观察的设置存储，用于 EnvironmentObject 注入
/// 封装 SettingsManager，当设置变更时自动触发 UI 更新
final class SettingsManagerStore: ObservableObject {

    @Published var settings: AppSettings

    private let manager: SettingsManager

    init(manager: SettingsManager = SettingsManager()) {
        self.manager = manager
        self.settings = manager.load()
    }

    /// 将当前设置持久化到磁盘
    func saveSettings() {
        try? manager.save(settings)
    }

    /// 从磁盘重新加载设置
    func reloadSettings() {
        settings = manager.load()
    }
}
