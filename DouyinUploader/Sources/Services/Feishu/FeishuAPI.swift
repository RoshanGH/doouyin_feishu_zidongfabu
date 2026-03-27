import Foundation

// MARK: - 飞书 API 错误

/// 飞书 API 调用错误
enum FeishuAPIError: LocalizedError {
    case networkError(Error)
    case httpError(statusCode: Int)
    case apiError(code: Int, message: String)
    case invalidResponse(String)
    case missingColumn(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "网络错误：\(error.localizedDescription)"
        case .httpError(let code):
            return "HTTP 请求失败，状态码：\(code)"
        case .apiError(let code, let message):
            return "飞书 API 错误（\(code)）：\(message)"
        case .invalidResponse(let detail):
            return "响应格式异常：\(detail)"
        case .missingColumn(let name):
            return "表格中缺少必要的列：\(name)"
        case .downloadFailed(let detail):
            return "附件下载失败：\(detail)"
        }
    }
}

// MARK: - 飞书 API 响应模型

/// 飞书记录字段值（多维表格字段的原始值）
typealias FeishuFieldValue = Any

/// 单条飞书记录
struct FeishuRecord {
    let recordId: String
    let fields: [String: Any]
}

/// fetchRecords 分页响应
private struct FetchPageResponse {
    let records: [FeishuRecord]
    let hasMore: Bool
    let nextPageToken: String?
}

// MARK: - 固定列名常量

/// 飞书表格的固定 9 列列名
enum FeishuColumn {
    static let douyinAccount  = "抖音账号"
    static let douyinName     = "抖音名称"
    static let material       = "作品素材"
    static let title          = "作品标题"
    static let content        = "作品文案"
    static let tags           = "话题标签"
    static let musicName      = "音乐名称"
    static let status         = "发布状态"
    static let publishTime    = "发布时间"
    static let scheduledTime  = "定时发布时间"
    static let failureReason  = "失败原因"

    /// 全部必须存在的列名列表
    static let required: [String] = [
        douyinAccount, material, title, content,
        tags, musicName, status, publishTime, scheduledTime, failureReason
    ]

    /// 全部列名（含可选列，用于引导展示）
    static let all: [(name: String, type: String, required: Bool, description: String)] = [
        (douyinAccount, "文本", true,  "抖音号，如 dyfx750s5c44"),
        (douyinName,    "文本", false, "抖音昵称，便于识别账号"),
        (material,      "附件", true,  "图片或视频文件"),
        (title,         "文本", false, "图文作品标题（视频可空）"),
        (content,       "文本", true,  "发布时的描述文案"),
        (tags,          "文本", false, "话题关键词，逗号分隔"),
        (musicName,     "文本", false, "抖音背景音乐名称"),
        (status,        "单选", true,  "允许发布/发布中/已发布/发布失败"),
        (publishTime,   "日期", false, "App 自动回写发布时间"),
        (scheduledTime, "日期", false, "格式：2026-03-26 18:00，为空则立即发布"),
        (failureReason, "文本", false, "App 自动回写失败原因"),
    ]
}

// MARK: - 飞书 API 客户端

/// 飞书多维表格 API 封装
final class FeishuAPI {

    private let authManager: FeishuAuthManager
    private let config: FeishuConfig
    private let baseURL: String
    private let session: URLSession

    /// - Parameters:
    ///   - config: 飞书配置
    ///   - baseURL: API 基础 URL（默认飞书国内）
    ///   - session: URLSession（测试时可注入 mock）
    init(
        config: FeishuConfig,
        baseURL: String = "https://open.feishu.cn/open-apis",
        session: URLSession = .shared
    ) {
        self.config = config
        self.baseURL = baseURL
        self.authManager = FeishuAuthManager(config: config, baseURL: baseURL)
        self.session = session
    }

    // MARK: - 读取记录（支持分页）

    /// 读取表格中的待发布记录，自动翻页直到获取全部数据
    /// - Parameters:
    ///   - filter: 飞书 filter 表达式（默认筛选待发布状态）
    /// - Returns: 所有匹配记录
    /// - Throws: FeishuAPIError / FeishuAuthError
    func fetchRecords(filter: String? = nil) async throws -> [FeishuRecord] {
        let token = try await authManager.getToken()
        var allRecords: [FeishuRecord] = []
        var pageToken: String? = nil

        // 默认筛选条件：允许发布、发布失败、发布中
        let filterExpression = filter ?? #"OR(CurrentValue.[发布状态]="允许发布",CurrentValue.[发布状态]="发布失败",CurrentValue.[发布状态]="发布中")"#

        repeat {
            // 构建查询参数
            var queryItems = [
                URLQueryItem(name: "page_size", value: "500"),
                URLQueryItem(name: "filter", value: filterExpression)
            ]
            if let pt = pageToken {
                queryItems.append(URLQueryItem(name: "page_token", value: pt))
            }

            let urlString = "\(baseURL)/bitable/v1/apps/\(config.appToken)/tables/\(config.tableId)/records"
            guard var components = URLComponents(string: urlString) else {
                throw FeishuAPIError.invalidResponse("无效的 API URL")
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw FeishuAPIError.invalidResponse("无法构建请求 URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let page = try await performRequest(request: request) { data in
                try self.parseFetchPage(data: data)
            }

            allRecords.append(contentsOf: page.records)
            pageToken = page.hasMore ? page.nextPageToken : nil

        } while pageToken != nil

        return allRecords
    }

    // MARK: - 更新记录

    /// 更新表格中的单条记录
    /// - Parameters:
    ///   - recordId: 记录 ID（record_id）
    ///   - fields: 要更新的字段键值对（仅传需要修改的字段）
    /// - Throws: FeishuAPIError / FeishuAuthError
    func updateRecord(recordId: String, fields: [String: Any]) async throws {
        let token = try await authManager.getToken()

        let urlString = "\(baseURL)/bitable/v1/apps/\(config.appToken)/tables/\(config.tableId)/records/\(recordId)"
        guard let url = URL(string: urlString) else {
            throw FeishuAPIError.invalidResponse("无效的 API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["fields": fields]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        try await performRequestVoid(request: request) { data in
            try self.validateAPIResponse(data: data)
        }
    }

    // MARK: - 下载附件

    /// 下载飞书附件到临时目录
    /// - Parameters:
    ///   - fileToken: 附件的 file_token
    ///   - fileName: 保存的文件名（含扩展名）
    /// - Returns: 临时文件 URL
    /// - Throws: FeishuAPIError / FeishuAuthError
    func downloadAttachment(fileToken: String, fileName: String) async throws -> URL {
        let token = try await authManager.getToken()

        // 飞书附件下载 API
        let urlString = "\(baseURL)/drive/v1/medias/\(fileToken)/download"
        guard let url = URL(string: urlString) else {
            throw FeishuAPIError.invalidResponse("无效的附件下载 URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // 执行下载
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeishuAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeishuAPIError.invalidResponse("非 HTTP 响应")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw FeishuAPIError.httpError(statusCode: httpResponse.statusCode)
        }
        guard !data.isEmpty else {
            throw FeishuAPIError.downloadFailed("下载内容为空")
        }

        // 保存到临时目录
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("douyin-uploader", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let destURL = tempDir.appendingPathComponent(fileName)
        try data.write(to: destURL, options: .atomic)

        return destURL
    }

    // MARK: - 测试连接

    /// 测试飞书配置的连通性
    /// 1. 验证认证是否成功
    /// 2. 验证能否访问指定表格
    /// 3. 校验表格是否含有全部必要列名
    /// - Returns: 测试通过时返回表格记录数；失败时抛出异常
    /// - Throws: FeishuAPIError / FeishuAuthError
    @discardableResult
    func testConnection() async throws -> Int {
        // 第一步：验证认证（调用 getToken 确保凭证有效）
        let token = try await authManager.getToken()

        // 第二步：读取表格字段元数据，验证列名
        let fieldsURL = "\(baseURL)/bitable/v1/apps/\(config.appToken)/tables/\(config.tableId)/fields"
        guard let url = URL(string: fieldsURL) else {
            throw FeishuAPIError.invalidResponse("无效的 API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let fieldNames = try await performRequest(request: request) { data in
            try self.parseFieldNames(data: data)
        }

        // 检查必要列是否都存在
        for required in FeishuColumn.required {
            guard fieldNames.contains(required) else {
                throw FeishuAPIError.missingColumn(required)
            }
        }

        // 第三步：获取记录总数（page_size=1，只取数量）
        let recordCount = try await fetchRecordCount(token: token)

        return recordCount
    }

    // MARK: - 私有辅助方法

    /// 执行 HTTP 请求并解析响应
    private func performRequest<T>(
        request: URLRequest,
        parser: (Data) throws -> T
    ) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeishuAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeishuAPIError.invalidResponse("非 HTTP 响应")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw FeishuAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        return try parser(data)
    }

    /// 执行 HTTP 请求，无需返回值（只做错误校验）
    private func performRequestVoid(
        request: URLRequest,
        validator: (Data) throws -> Void
    ) async throws {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeishuAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeishuAPIError.invalidResponse("非 HTTP 响应")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw FeishuAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        try validator(data)
    }

    /// 解析 fetchRecords 的分页响应
    private func parseFetchPage(data: Data) throws -> FetchPageResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FeishuAPIError.invalidResponse("无法解析 JSON")
        }

        let code = json["code"] as? Int ?? -1
        guard code == 0 else {
            let message = json["msg"] as? String ?? "未知错误"
            throw FeishuAPIError.apiError(code: code, message: message)
        }

        guard let responseData = json["data"] as? [String: Any] else {
            throw FeishuAPIError.invalidResponse("响应缺少 data 字段")
        }

        let items = responseData["items"] as? [[String: Any]] ?? []
        let records: [FeishuRecord] = items.compactMap { item in
            guard let recordId = item["record_id"] as? String,
                  let fields = item["fields"] as? [String: Any] else {
                return nil
            }
            return FeishuRecord(recordId: recordId, fields: fields)
        }

        let hasMore = responseData["has_more"] as? Bool ?? false
        let nextPageToken = responseData["page_token"] as? String

        return FetchPageResponse(records: records, hasMore: hasMore, nextPageToken: nextPageToken)
    }

    /// 校验 API 响应的 code 是否为 0
    private func validateAPIResponse(data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FeishuAPIError.invalidResponse("无法解析 JSON")
        }
        let code = json["code"] as? Int ?? -1
        guard code == 0 else {
            let message = json["msg"] as? String ?? "未知错误"
            throw FeishuAPIError.apiError(code: code, message: message)
        }
    }

    /// 解析字段元数据，返回所有字段名称列表
    private func parseFieldNames(data: Data) throws -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FeishuAPIError.invalidResponse("无法解析字段 JSON")
        }

        let code = json["code"] as? Int ?? -1
        guard code == 0 else {
            let message = json["msg"] as? String ?? "未知错误"
            throw FeishuAPIError.apiError(code: code, message: message)
        }

        guard let responseData = json["data"] as? [String: Any],
              let items = responseData["items"] as? [[String: Any]] else {
            throw FeishuAPIError.invalidResponse("响应缺少字段列表")
        }

        return items.compactMap { $0["field_name"] as? String }
    }

    /// 获取表格记录总数（只读一页数据）
    private func fetchRecordCount(token: String) async throws -> Int {
        let queryItems = [
            URLQueryItem(name: "page_size", value: "1")
        ]

        let urlString = "\(baseURL)/bitable/v1/apps/\(config.appToken)/tables/\(config.tableId)/records"
        guard var components = URLComponents(string: urlString) else {
            throw FeishuAPIError.invalidResponse("无效的 API URL")
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw FeishuAPIError.invalidResponse("无法构建请求 URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(request: request) { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = json["data"] as? [String: Any] else {
                throw FeishuAPIError.invalidResponse("无法解析记录数响应")
            }
            return responseData["total"] as? Int ?? 0
        }
    }
}
