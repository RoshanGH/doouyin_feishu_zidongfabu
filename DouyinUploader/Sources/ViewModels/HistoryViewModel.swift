import Foundation
import SwiftUI

/// 历史记录页面的 ViewModel
@MainActor
final class HistoryViewModel: ObservableObject {

    /// 日志摘要列表（entries 为空）
    @Published private(set) var historyList: [ExecutionLog] = []
    /// 当前选中的完整日志（含 entries）
    @Published private(set) var selectedLog: ExecutionLog?
    /// 错误提示
    @Published var errorMessage: String?
    /// 导出面板显示的 URL
    @Published var exportURL: URL?
    /// 是否正在加载
    @Published private(set) var isLoading: Bool = false

    private let logStore: LogStore

    init(logStore: LogStore = LogStore()) {
        self.logStore = logStore
    }

    // MARK: - 加载历史

    /// 加载全部日志摘要
    func loadHistory() {
        isLoading = true
        let list = logStore.loadAll()
        historyList = list
        isLoading = false
    }

    // MARK: - 选中日志

    /// 选中并加载完整日志
    /// - Parameter id: 日志 ID
    func selectLog(id: UUID) {
        if let full = logStore.loadLog(id: id) {
            selectedLog = full
        } else {
            // 找不到完整日志时回退到摘要
            selectedLog = historyList.first { $0.id == id }
        }
    }

    /// 取消选中
    func clearSelection() {
        selectedLog = nil
    }

    // MARK: - 导出

    /// 导出指定 ID 的日志
    /// - Parameter id: 日志 ID
    func exportLog(id: UUID) {
        guard let log = logStore.loadLog(id: id) ?? historyList.first(where: { $0.id == id }) else {
            errorMessage = "找不到要导出的日志"
            return
        }

        do {
            let url = try logStore.exportLog(log)
            exportURL = url
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 删除

    /// 删除指定 ID 的日志
    /// - Parameter id: 日志 ID
    func deleteLog(id: UUID) {
        logStore.deleteLog(id: id)
        historyList = historyList.filter { $0.id != id }
        if selectedLog?.id == id {
            selectedLog = nil
        }
    }
}
