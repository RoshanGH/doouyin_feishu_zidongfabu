import XCTest
@testable import DouyinUploader

final class AppSettingsTests: XCTestCase {

    // MARK: - 默认值测试

    func testDefaultValues() {
        let settings = AppSettings()
        XCTAssertEqual(settings.taskIntervalMin, 5)
        XCTAssertEqual(settings.taskIntervalMax, 15)
        XCTAssertEqual(settings.jsDelayMin, 0.5)
        XCTAssertEqual(settings.jsDelayMax, 2.0)
        XCTAssertEqual(settings.batchLimit, 10)
        XCTAssertEqual(settings.batchWaitMinutes, 5)
        XCTAssertEqual(settings.logRetentionDays, 30)
        XCTAssertTrue(settings.enableNotification)
        XCTAssertTrue(settings.preventSleep)
        XCTAssertFalse(settings.debugMode)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }

    // MARK: - 不可变模式测试

    func testImmutableUpdate() {
        let original = AppSettings()
        var updated = original
        updated.debugMode = true
        updated.batchLimit = 20

        // 原始值不变
        XCTAssertFalse(original.debugMode)
        XCTAssertEqual(original.batchLimit, 10)
        // 新值已更新
        XCTAssertTrue(updated.debugMode)
        XCTAssertEqual(updated.batchLimit, 20)
    }

    // MARK: - Codable 序列化测试

    func testCodableRoundTrip() throws {
        var settings = AppSettings()
        settings.taskIntervalMin = 3
        settings.taskIntervalMax = 20
        settings.batchLimit = 15
        settings.debugMode = true
        settings.hasCompletedOnboarding = true

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.taskIntervalMin, 3)
        XCTAssertEqual(decoded.taskIntervalMax, 20)
        XCTAssertEqual(decoded.batchLimit, 15)
        XCTAssertTrue(decoded.debugMode)
        XCTAssertTrue(decoded.hasCompletedOnboarding)
    }

    // MARK: - Equatable 测试

    func testEquatable() {
        let a = AppSettings()
        let b = AppSettings()
        XCTAssertEqual(a, b)

        var c = AppSettings()
        c.debugMode = true
        XCTAssertNotEqual(a, c)
    }
}

// MARK: - SettingsManager 测试

final class SettingsManagerTests: XCTestCase {

    private var tempDir: URL!
    private var manager: SettingsManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsManagerTests_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("settings.json")
        manager = SettingsManager(fileURL: fileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLoadReturnsDefaultWhenFileNotExists() {
        let settings = manager.load()
        XCTAssertEqual(settings, AppSettings())
    }

    func testSaveAndLoad() throws {
        var settings = AppSettings()
        settings.batchLimit = 25
        settings.debugMode = true
        settings.hasCompletedOnboarding = true

        try manager.save(settings)
        let loaded = manager.load()

        XCTAssertEqual(loaded.batchLimit, 25)
        XCTAssertTrue(loaded.debugMode)
        XCTAssertTrue(loaded.hasCompletedOnboarding)
    }

    func testSaveOverwritesPreviousSettings() throws {
        var first = AppSettings()
        first.batchLimit = 5
        try manager.save(first)

        var second = AppSettings()
        second.batchLimit = 50
        try manager.save(second)

        let loaded = manager.load()
        XCTAssertEqual(loaded.batchLimit, 50)
    }

    func testLoadReturnsDefaultOnCorruptFile() throws {
        let fileURL = tempDir.appendingPathComponent("settings.json")
        try "not valid json".data(using: .utf8)!.write(to: fileURL)

        let settings = manager.load()
        // 损坏文件时应返回默认值
        XCTAssertEqual(settings, AppSettings())
    }
}
