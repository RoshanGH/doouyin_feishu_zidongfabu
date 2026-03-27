import XCTest
@testable import DouyinUploader

// MARK: - SelectorConfig 加载与解析测试

final class SelectorConfigTests: XCTestCase {

    // MARK: - defaultConfig 测试

    func test_defaultConfig_hasCorrectUploadURL() {
        let config = SelectorConfig.defaultConfig
        XCTAssertEqual(
            config.common.uploadPageURL,
            "https://creator.douyin.com/creator-micro/content/upload"
        )
    }

    func test_defaultConfig_hasAllRequiredSelectors() {
        let config = SelectorConfig.defaultConfig
        XCTAssertFalse(config.common.publishButton.isEmpty)
        XCTAssertFalse(config.common.descriptionEditor.isEmpty)
        XCTAssertFalse(config.common.scheduleInput.isEmpty)
        XCTAssertFalse(config.videoUpload.fileInput.isEmpty)
        XCTAssertFalse(config.imageUpload.fileInput.isEmpty)
    }

    func test_defaultConfig_hasSuccessAndFailureKeywords() {
        let config = SelectorConfig.defaultConfig
        XCTAssertFalse(config.successKeywords.isEmpty)
        XCTAssertFalse(config.failureKeywords.isEmpty)
        XCTAssertTrue(config.successKeywords.contains("发布成功"))
        XCTAssertTrue(config.failureKeywords.contains("发布失败"))
    }

    func test_defaultConfig_videoUploadCompleteText() {
        let config = SelectorConfig.defaultConfig
        XCTAssertEqual(config.videoUpload.uploadCompleteText, "重新上传")
    }

    func test_defaultConfig_imageModeSwitchText() {
        let config = SelectorConfig.defaultConfig
        XCTAssertEqual(config.imageUpload.modeSwitchText, "发布图文")
    }

    func test_defaultConfig_version() {
        let config = SelectorConfig.defaultConfig
        XCTAssertFalse(config.version.isEmpty)
    }

    // MARK: - JSON 解码测试

    func test_decode_validJSON_succeeds() throws {
        let json = """
        {
            "version": "2.0.0",
            "common": {
                "upload_page_url": "https://example.com/upload",
                "publish_button": ".btn-publish",
                "publish_button_text": "发布",
                "description_editor": ".editor",
                "schedule_radio": ".radio",
                "schedule_radio_text": "定时发布",
                "schedule_input": ".time-input"
            },
            "video_upload": {
                "file_input": "input[type=file]",
                "upload_complete_marker": ".card",
                "upload_complete_text": "重新上传",
                "upload_progress": ".progress"
            },
            "image_upload": {
                "mode_switch_text": "发布图文",
                "file_input": "input[accept*=image]",
                "file_input_fallback": "input",
                "title_input": "input.title",
                "upload_item": ".upload-item",
                "upload_complete_text": "添加图片"
            },
            "success_keywords": ["发布成功"],
            "failure_keywords": ["发布失败"]
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let config = try JSONDecoder().decode(SelectorConfig.self, from: data)

        XCTAssertEqual(config.version, "2.0.0")
        XCTAssertEqual(config.common.uploadPageURL, "https://example.com/upload")
        XCTAssertEqual(config.common.publishButton, ".btn-publish")
        XCTAssertEqual(config.videoUpload.fileInput, "input[type=file]")
        XCTAssertEqual(config.imageUpload.modeSwitchText, "发布图文")
        XCTAssertEqual(config.successKeywords, ["发布成功"])
        XCTAssertEqual(config.failureKeywords, ["发布失败"])
    }

    func test_decode_missingField_throws() {
        // 缺少必填字段 "version"
        let json = """
        {
            "common": {
                "upload_page_url": "https://example.com"
            }
        }
        """

        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(
            try JSONDecoder().decode(SelectorConfig.self, from: data)
        )
    }

    func test_decode_emptyData_throws() {
        let data = Data()
        XCTAssertThrowsError(
            try JSONDecoder().decode(SelectorConfig.self, from: data)
        )
    }

    // MARK: - Equatable 测试

    func test_equatable_sameConfigs_areEqual() {
        let config1 = SelectorConfig.defaultConfig
        let config2 = SelectorConfig.defaultConfig
        XCTAssertEqual(config1, config2)
    }

    func test_equatable_differentVersion_areNotEqual() throws {
        let json1 = makeValidJSON(version: "1.0.0")
        let json2 = makeValidJSON(version: "2.0.0")

        let config1 = try JSONDecoder().decode(SelectorConfig.self, from: json1.data(using: .utf8)!)
        let config2 = try JSONDecoder().decode(SelectorConfig.self, from: json2.data(using: .utf8)!)

        XCTAssertNotEqual(config1, config2)
    }

    // MARK: - SelectorConfigLoader 测试

    func test_loader_loadsFromBundle_succeeds() throws {
        let loader = SelectorConfigLoader()
        // Bundle.module 中应该存在 selectors.json
        // 如果找不到会抛出 bundleResourceNotFound 错误
        // 测试环境下直接测试 defaultConfig 作为 fallback
        let config = try loader.load()
        XCTAssertFalse(config.version.isEmpty)
        XCTAssertFalse(config.common.uploadPageURL.isEmpty)
    }

    func test_loader_decodesAllFields() throws {
        let loader = SelectorConfigLoader()
        let config = try loader.load()

        // 验证所有关键字段不为空
        XCTAssertFalse(config.common.publishButton.isEmpty)
        XCTAssertFalse(config.common.descriptionEditor.isEmpty)
        XCTAssertFalse(config.videoUpload.fileInput.isEmpty)
        XCTAssertFalse(config.videoUpload.uploadCompleteText.isEmpty)
        XCTAssertFalse(config.imageUpload.modeSwitchText.isEmpty)
        XCTAssertFalse(config.imageUpload.fileInput.isEmpty)
        XCTAssertFalse(config.successKeywords.isEmpty)
        XCTAssertFalse(config.failureKeywords.isEmpty)
    }

    // MARK: - SelectorConfigError 测试

    func test_selectorConfigError_descriptions_notEmpty() {
        let errors: [SelectorConfigError] = [
            .bundleResourceNotFound,
            .decodingFailed("test error"),
            .invalidData
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) 的描述不应为空")
        }
    }

    // MARK: - 辅助方法

    private func makeValidJSON(version: String) -> String {
        """
        {
            "version": "\(version)",
            "common": {
                "upload_page_url": "https://creator.douyin.com/creator-micro/content/upload",
                "publish_button": "button[class*='primary']",
                "publish_button_text": "发布",
                "description_editor": ".zone-container",
                "schedule_radio": "[class^='radio']",
                "schedule_radio_text": "定时发布",
                "schedule_input": ".semi-input"
            },
            "video_upload": {
                "file_input": "div[class^='container'] input",
                "upload_complete_marker": "[class^='long-card']",
                "upload_complete_text": "重新上传",
                "upload_progress": "[class*='progress']"
            },
            "image_upload": {
                "mode_switch_text": "发布图文",
                "file_input": "div[class^='container'] input[accept*='image']",
                "file_input_fallback": "div[class^='container'] input",
                "title_input": "input[placeholder*='标题']",
                "upload_item": "[class*='upload-item']",
                "upload_complete_text": "添加图片"
            },
            "success_keywords": ["发布成功", "已发布"],
            "failure_keywords": ["发布失败", "上传失败"]
        }
        """
    }
}
