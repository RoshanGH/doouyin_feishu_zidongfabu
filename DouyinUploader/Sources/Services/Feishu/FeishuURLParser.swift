import Foundation

/// 飞书 URL 解析结果
struct FeishuURLParseResult: Equatable {
    let appToken: String
    let tableId: String?
    let isLark: Bool   // true = 国际版（larksuite.com），false = 国内版（feishu.cn）

    /// API 基础 URL
    var apiBaseURL: String {
        isLark
            ? "https://open.larksuite.com/open-apis"
            : "https://open.feishu.cn/open-apis"
    }
}

/// 解析飞书多维表格 URL，提取 App Token 和 Table ID
/// 支持的 URL 格式：
///   https://xxx.feishu.cn/base/{app_token}?table={table_id}
///   https://xxx.feishu.cn/wiki/{app_token}?table={table_id}
///   https://xxx.larksuite.com/base/{app_token}?table={table_id}
///   https://xxx.larksuite.com/wiki/{app_token}?table={table_id}
func parseFeishuURL(_ urlString: String) -> FeishuURLParseResult? {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let url = URL(string: trimmed) else { return nil }
    guard let host = url.host else { return nil }

    // 判断是飞书还是 Lark
    let isLark: Bool
    if host.contains("feishu.cn") {
        isLark = false
    } else if host.contains("larksuite.com") {
        isLark = true
    } else {
        return nil
    }

    // 提取 app_token: /base/{app_token} 或 /wiki/{app_token} 路径段
    let pathComponents = url.pathComponents
    let supportedPrefixes = ["base", "wiki"]
    var appToken: String?

    for prefix in supportedPrefixes {
        if let prefixIndex = pathComponents.firstIndex(of: prefix),
           prefixIndex + 1 < pathComponents.count {
            let token = pathComponents[prefixIndex + 1]
            if !token.isEmpty {
                appToken = token
                break
            }
        }
    }

    guard let appToken, !appToken.isEmpty else { return nil }

    // 提取 table_id: 查询参数 table
    let tableId: String?
    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
       let tableParam = components.queryItems?.first(where: { $0.name == "table" })?.value,
       !tableParam.isEmpty {
        tableId = tableParam
    } else {
        tableId = nil
    }

    return FeishuURLParseResult(appToken: appToken, tableId: tableId, isLark: isLark)
}

/// 解析话题标签字符串，支持逗号、换行、#号 分隔
/// 输入: "#女装\n#男装"  或  "美食,探店, 深圳"  或  "#美食 #探店"
/// 输出: ["女装", "男装"]  或  ["美食", "探店", "深圳"]  或  ["美食", "探店"]
func parseTags(_ tagString: String?) -> [String] {
    guard let tagString, !tagString.isEmpty else { return [] }
    // 先统一把换行和逗号都替换成逗号，再按逗号分割
    let normalized = tagString
        .replacingOccurrences(of: "\n", with: ",")
        .replacingOccurrences(of: "\r", with: ",")
    return normalized
        .split(separator: ",")
        .map {
            $0.trimmingCharacters(in: .whitespaces)
              .replacingOccurrences(of: "#", with: "")  // 去掉 # 前缀
        }
        .filter { !$0.isEmpty }
}
