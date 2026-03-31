import Foundation

/// CDP 浏览器驱动协议 — 只定义原子操作，不含业务逻辑
protocol CDPDriver {
    func screenshot() async throws -> Data
    func click(x: Int, y: Int) async throws
    func type(text: String) async throws
    func pressKey(_ key: String) async throws
    func uploadFiles(selector: String, paths: [String]) async throws
    func scroll(deltaX: Int, deltaY: Int) async throws
    func navigate(to url: String) async throws
    func getCurrentURL() async throws -> String
    func evaluate(_ js: String) async throws -> Any?
}
