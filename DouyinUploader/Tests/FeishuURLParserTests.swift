import Testing
@testable import DouyinUploader

@Suite("飞书 URL 解析测试")
struct FeishuURLParserTests {

    // MARK: - 正常解析

    @Test("完整飞书 URL 解析成功")
    func parseFullFeishuURL() {
        let result = parseFeishuURL("https://example.feishu.cn/base/VwGhbXXX?table=tblYYY&view=vewZZZ")
        #expect(result != nil)
        #expect(result?.appToken == "VwGhbXXX")
        #expect(result?.tableId == "tblYYY")
        #expect(result?.isLark == false)
        #expect(result?.apiBaseURL == "https://open.feishu.cn/open-apis")
    }

    @Test("wiki 路径的飞书 URL 解析成功")
    func parseWikiURL() {
        let result = parseFeishuURL("https://tdsoxbgmed.feishu.cn/wiki/XBTQwV8leihuomkPNmgcJkySnBe?table=tblb9PsTMkrsfoj2&view=vew5bAnqLm&open_in_browser=true")
        #expect(result != nil)
        #expect(result?.appToken == "XBTQwV8leihuomkPNmgcJkySnBe")
        #expect(result?.tableId == "tblb9PsTMkrsfoj2")
        #expect(result?.isLark == false)
    }

    @Test("Lark 国际版 URL 解析成功")
    func parseLarkURL() {
        let result = parseFeishuURL("https://example.larksuite.com/base/AbcToken?table=tblTest")
        #expect(result != nil)
        #expect(result?.appToken == "AbcToken")
        #expect(result?.tableId == "tblTest")
        #expect(result?.isLark == true)
        #expect(result?.apiBaseURL == "https://open.larksuite.com/open-apis")
    }

    @Test("URL 不含 table 参数时 tableId 为 nil")
    func parseURLWithoutTable() {
        let result = parseFeishuURL("https://example.feishu.cn/base/TokenXXX")
        #expect(result != nil)
        #expect(result?.appToken == "TokenXXX")
        #expect(result?.tableId == nil)
    }

    @Test("URL 前后有空格时自动 trim")
    func parseURLWithWhitespace() {
        let result = parseFeishuURL("  https://example.feishu.cn/base/TokenXXX?table=tblYYY  ")
        #expect(result != nil)
        #expect(result?.appToken == "TokenXXX")
    }

    // MARK: - 异常 URL

    @Test("非飞书域名返回 nil")
    func parseNonFeishuURL() {
        let result = parseFeishuURL("https://google.com/base/xxx")
        #expect(result == nil)
    }

    @Test("无 /base/ 路径返回 nil")
    func parseURLWithoutBasePath() {
        let result = parseFeishuURL("https://example.feishu.cn/docs/xxx")
        #expect(result == nil)
    }

    @Test("空字符串返回 nil")
    func parseEmptyString() {
        let result = parseFeishuURL("")
        #expect(result == nil)
    }

    @Test("无效 URL 返回 nil")
    func parseInvalidURL() {
        let result = parseFeishuURL("not a url at all")
        #expect(result == nil)
    }
}

@Suite("话题标签解析测试")
struct TagParserTests {

    @Test("正常解析逗号分隔的标签")
    func parseCommaSeparated() {
        let tags = parseTags("美食,探店,深圳")
        #expect(tags == ["美食", "探店", "深圳"])
    }

    @Test("自动去除前后空格")
    func parseWithSpaces() {
        let tags = parseTags("美食 , 探店 , 深圳 ")
        #expect(tags == ["美食", "探店", "深圳"])
    }

    @Test("空字符串返回空数组")
    func parseEmptyString() {
        let tags = parseTags("")
        #expect(tags.isEmpty)
    }

    @Test("nil 返回空数组")
    func parseNil() {
        let tags = parseTags(nil)
        #expect(tags.isEmpty)
    }

    @Test("单个标签")
    func parseSingleTag() {
        let tags = parseTags("美食")
        #expect(tags == ["美食"])
    }

    @Test("连续逗号过滤空值")
    func parseConsecutiveCommas() {
        let tags = parseTags("美食,,探店")
        #expect(tags == ["美食", "探店"])
    }
}
