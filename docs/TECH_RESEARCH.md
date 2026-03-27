# 技术调研报告

> 调研日期：2026-03-25 | 最后更新：2026-03-26

## 目录

- [技术约束](#技术约束) — macOS 版本、语言、依赖、分发
- [一、飞书多维表格 API](#一飞书多维表格-api) — 认证方式、API 能力、分页、附件下载、PAT 过期
- [二、抖音创作者中心](#二抖音创作者中心) — 发布方式选型、登录流程、WKWebView 方案（off-screen/Cookie/文件上传/React兼容）
- [三、风险评估](#三风险评估) — 风险矩阵 + 防风控策略 + 休眠防护
- [四、飞书 URL 解析规则](#四飞书-url-解析规则)
- [五、JS 选择器管理方案](#五js-选择器管理方案)
- [六、建议代码架构](#六建议代码架构) — MVVM 分层 + 文件结构
- [七、App 本地存储路径汇总](#七app-本地存储路径汇总)
- [八、日志文件格式](#八日志文件格式) — JSON 结构、日志级别
- [九、术语定义](#九术语定义)

## 技术约束

| 约束 | 值 | 说明 |
|------|-----|------|
| 最低 macOS 版本 | macOS 13.0 (Ventura) | NavigationSplitView 需 13+ |
| 开发语言 | Swift 5.9+ | async/await、Observation 等 |
| 第三方依赖 | **零** | 全部使用 Apple 系统框架 |
| 分发方式 | 直接分发 | 不上架 App Store，不开启 Sandbox |

## 一、飞书多维表格 API

### API 域名

| 版本 | 域名 |
|------|------|
| 飞书（国内版） | `https://open.feishu.cn/open-apis` |
| Lark（国际版） | `https://open.larksuite.com/open-apis` |

App 中应根据用户粘贴的 URL 自动判断（域名含 `feishu.cn` → 国内版，含 `larksuite.com` → 国际版），或在配置中提供选项。

### 请求格式

所有飞书 API 请求的通用 Headers：
```
Authorization: Bearer {token}    // PAT 或 tenant_access_token
Content-Type: application/json
```

### 认证方式

| 方案 | 复杂度 | 说明 |
|------|--------|------|
| **Personal Access Token (PAT)** | 最低 | 个人令牌，需企业管理员开放，有效期最长 180 天 |
| **自建应用 tenant_access_token** | 中等 | 需创建飞书应用，获取 App ID + Secret，token 有效期 2h 可自动刷新 |
| OAuth user_access_token | 较高 | 脚本场景不推荐 |

### 结论

- **优先尝试 PAT**，最简单；如企业未开放，降级到自建应用方案
- 应用中同时支持两种认证方式，让用户自选

### API 能力确认

| 需求 | 是否支持 | 接口 |
|------|----------|------|
| 读取指定页签数据 | 支持 | `GET /bitable/v1/apps/{app_token}/tables/{table_id}/records` |
| 按条件筛选行 | 支持 | `filter=OR(CurrentValue.[发布状态]="允许发布",CurrentValue.[发布状态]="发布失败",CurrentValue.[发布状态]="发布中")` |
| 修改行数据（回写状态/时间） | 支持 | `PATCH .../records/{record_id}` 或批量 `batch_update` |
| 读取附件字段（素材下载） | 支持 | 附件字段返回 file_token，通过 `/drive/v1/medias/{file_token}/download` 下载 |

### 飞书 API 分页

飞书多维表格 API 单次请求最多返回 500 条记录，超过需要分页拉取：

```
GET /bitable/v1/apps/{app_token}/tables/{table_id}/records
    ?page_size=500
    &page_token=xxx    // 首次请求不传，后续传上次返回的 page_token
    &filter=OR(CurrentValue.[发布状态]="允许发布",CurrentValue.[发布状态]="发布失败",CurrentValue.[发布状态]="发布中")

返回：
{
  "data": {
    "items": [...],
    "page_token": "下一页token",    // 为空则无更多数据
    "has_more": true/false,
    "total": 1234
  }
}
```

实现时循环拉取直到 `has_more = false`。

### 飞书单选字段 JSON 结构

飞书多维表格中，单选类型字段（如"发布状态"）读写格式：

```json
// 读取时返回：
{ "发布状态": "允许发布" }   // 直接返回选项文本

// 写入时：
{
  "fields": {
    "发布状态": "已发布"      // 直接传选项文本，飞书自动匹配已有选项
  }
}
```

> 如果写入的选项文本在飞书单选列中不存在，飞书会自动创建该选项。因此需确保代码中的状态字符串与飞书表格中的选项完全一致（包括中文标点）。

### 飞书回写完整请求示例

发布成功后回写飞书：

```
PATCH https://open.feishu.cn/open-apis/bitable/v1/apps/{app_token}/tables/{table_id}/records/{record_id}
Authorization: Bearer {token}
Content-Type: application/json

{
  "fields": {
    "发布状态": "已发布",
    "发布时间": 1711432800000,
    "失败原因": ""
  }
}
```

发布失败后回写：
```
{
  "fields": {
    "发布状态": "发布失败",
    "失败原因": "上传超时"
  }
}
```

开始执行时标记为"发布中"：
```
{
  "fields": {
    "发布状态": "发布中",
    "失败原因": ""
  }
}
```

### 飞书回写策略选择

| 策略 | 优点 | 缺点 | 选用 |
|------|------|------|------|
| **单条即时回写** | App 崩溃时丢失最少；飞书端实时可见状态 | API 调用次数多 | **是** |
| 批量回写（每 N 条一批） | 减少 API 调用 | 崩溃可能丢失一批状态；飞书端更新延迟 | 否 |

由于串行执行本身较慢（每条 30s~2min），API 调用频率不会超过飞书限流阈值，因此选择**单条即时回写**。

### 飞书日期字段处理

飞书日期字段存储和传递的是**毫秒级 Unix 时间戳**：

```json
// 读取定时发布时间：
{ "定时发布时间": 1711432800000 }   // 毫秒时间戳

// 回写发布时间：
{
  "fields": {
    "发布时间": 1711432800000       // 毫秒时间戳
  }
}
```

**时区处理**：
- 飞书 API 返回的时间戳是 UTC
- App 读取后需转换为用户本地时区展示
- 定时发布时间在传给抖音时需转为**北京时间**（抖音服务器时区）
- 回写"发布时间"时使用当前时刻的 UTC 毫秒时间戳：`Date().timeIntervalSince1970 * 1000`

### 飞书附件字段 JSON 结构

飞书多维表格中，附件类型字段返回的 JSON 格式如下：

```json
{
  "作品素材": [
    {
      "file_token": "boxcnXXXXXX",
      "name": "video.mp4",
      "type": "video/mp4",       // MIME 类型，用于区分图片/视频
      "size": 12345678,           // 字节大小
      "url": "https://..."        // 临时下载 URL（有时效）
    },
    {
      "file_token": "boxcnYYYYYY",
      "name": "photo.jpg",
      "type": "image/jpeg",
      "size": 234567,
      "url": "https://..."
    }
  ]
}
```

**素材类型判断逻辑**：
- `type` 以 `image/` 开头 → 图片
- `type` 以 `video/` 开头 → 视频
- 其他 → 不支持的格式

### 飞书附件下载注意事项

- 附件下载需要与读取记录相同的认证 token（PAT 或 tenant_access_token）
- 大视频文件（数百 MB~几 GB）下载需要：
  - 使用 URLSession 的 downloadTask（非 dataTask），支持断点续传
  - 写入本地临时目录 `FileManager.default.temporaryDirectory`
  - 下载完成后校验文件大小是否与飞书返回的 size 一致
- 飞书附件 URL 有时效性，获取后需尽快下载

### 飞书 API 速率限制

- 飞书 API 有请求频率限制（Rate Limit），通常为 100 次/分钟/应用
- 响应头中包含 `X-Ogw-RateLimit-Remaining` 和 `X-Ogw-RateLimit-Reset` 字段
- 当触发限流时返回 HTTP 429，App 应等待 `Retry-After` 指定的秒数后重试
- 在我们的场景中：每条任务可能触发 1 次读取 + 1~2 次回写 + 1 次附件下载 = 约 3~4 次 API 调用
- 按串行执行且每条任务间隔 5~15 秒，通常不会触发限流

### 获取 tenant_access_token

当用户选择"自建应用"认证方式时，需要用 App ID + App Secret 获取 token：

```
POST https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal
Content-Type: application/json

{
  "app_id": "cli_xxxxxx",
  "app_secret": "xxxxxx"
}

→ 响应:
{
  "code": 0,
  "tenant_access_token": "t-xxxxxx",
  "expire": 7200    // 秒，即 2 小时
}
```

App 应在内存中缓存 token 和过期时间，过期前 5 分钟自动刷新。

### 飞书 API 常见错误码

| 错误码 | 含义 | App 中的处理 |
|--------|------|-------------|
| 0 | 成功 | 正常处理 |
| 99991668 | token 无效 | 提示用户检查 PAT / App Secret |
| 99991663 | token 过期 | 自动刷新（tenant_token）或提示更新（PAT） |
| 1254043 | 无权限访问该文档 | 提示用户检查表格分享权限 |
| 1254040 | 表格不存在 | 提示检查 App Token 或 Table ID |
| 1254014 | 字段不存在 | 提示缺少必要的列 |

### PAT 过期处理

- PAT 有效期最长 180 天，过期后 API 返回 401
- App 应在请求失败时检测 401 状态码，提示用户更新 PAT
- 自建应用的 tenant_access_token 有效期 2 小时，需自动刷新：
  - 每次 API 调用前检查 token 是否临近过期（提前 5 分钟刷新）
  - 或在收到 401 时自动重新获取 token 并重试

---

## 二、抖音创作者中心

### 发布方式最终选型

| 方案 | 可行性 | 稳定性 | 维护成本 | 选用 |
|------|--------|--------|----------|------|
| 逆向 Web API | 理论可行 | 差 | 极高 | **否** |
| Playwright 浏览器自动化 | 可行 | 好 | 中等 | **否**（需外部运行时，不够原生） |
| **WKWebView + JS 注入** | 可行 | 中等 | 中等 | **是（采用）** |

### 为什么选 WKWebView 而非 Playwright

- Playwright 需要捆绑 Node.js/Python 运行时（+150MB），违背"纯原生零依赖"原则
- **最终采用 Chrome for Testing + CDP**（自动下载 Chrome 二进制，通过 CDP WebSocket 控制）
- WKWebView 仅保留用于扫码登录弹窗
- CDP 的 `DOM.setFileInputFiles` 可直接设置文件路径，无需用户手势，比 WKWebView `runOpenPanel` 更可靠

### 逆向 API 不采用的原因

1. X-Bogus / a_bogus 签名算法经过 WASM + JS 高度混淆，频繁更新
2. msToken、ttwid 等多层防护
3. 行为分析 + TLS 指纹检测
4. 封号风险高

### 抖音关键 URL 汇总

| 用途 | URL | 备注 |
|------|-----|------|
| 创作者中心首页 | `https://creator.douyin.com` | 登录检测用 |
| 视频上传/发布页 | `https://creator.douyin.com/creator-micro/content/upload` | 上传入口 |
| 视频发布页（v2） | `https://creator.douyin.com/creator-micro/content/post/video?enter_from=publish_page` | 截图验证 |
| 图文发布页 | `https://creator.douyin.com/creator-micro/content/post/image?default_tab=3&enter_from=publish_page&media_type=image&ttype=new` | 截图验证 |
| 用户信息 API | `https://creator.douyin.com/web/api/media/user/info` | Cookie 检测 + 获取抖音号 |
| ~~SSO 获取二维码~~ | ~~`https://sso.douyin.com/get_qrcode/`~~ | ~~已弃用，改用 WKWebView 扫码~~ |
| ~~SSO 轮询状态~~ | ~~`https://sso.douyin.com/check_qrconnect/`~~ | ~~已弃用，改用 WKWebView 扫码~~ |
| 文章发布页（音乐下载用） | `https://creator.douyin.com/creator-micro/content/post/article?...` | MusicDownloader 搜索音乐 |

> 以上 URL 基于公开信息和逆向分析，部分可能变更，需在 Phase 0 中实际验证。

### 扫码登录流程（WKWebView 弹窗方式）

> **实际实现**采用 WKWebView 弹窗方式，而非纯 HTTP SSO API。原因：WKWebView 方式更可靠，能自动处理抖音页面的各种重定向和验证。

```
1. 用户点击"添加账号"，弹出 QRCodeLoginView（内嵌 WKWebView）
2. WKWebView 自动加载 https://creator.douyin.com（抖音创作者中心）
3. 页面自动跳转到登录页，显示扫码二维码
4. 用户用抖音 App 扫码 + 确认
5. 页面自动跳转回创作者中心
6. App 从 WKHTTPCookieStore 提取所有 Cookie
7. App 从 DOM 中提取用户信息（昵称、头像、抖音号）
8. Cookie 序列化为 CookieDTO JSON，base64 编码存入 secrets/ 目录
```

**App 中的实现**：
- `QRCodeLoginView`：SwiftUI sheet 弹窗，内嵌 WKWebView
- WKNavigationDelegate 监听页面跳转，检测登录成功（URL 变为创作者中心）
- 从 `WKHTTPCookieStore` 提取 Cookie，从 DOM 提取 `user_info` 数据
- Cookie 序列化为 `CookieDTO`（name, value, domain, path, isSecure, isHTTPOnly, expiresDate）

**关键实现细节 — Cookie 捕获**：
- 第 3 步访问 `redirect_url` 时，服务端通常返回 302 重定向，Cookie 在重定向响应的 `Set-Cookie` 头中
- URLSession 默认自动跟随重定向，可能导致 Cookie 丢失
- **解决方案**：实现 `URLSessionTaskDelegate.urlSession(_:task:willPerformHTTPRedirection:)` 拦截重定向，从 `response.allHeaderFields` 中提取 `Set-Cookie`

```swift
func urlSession(_ session: URLSession, task: URLSessionTask,
                willPerformHTTPRedirection response: HTTPURLResponse,
                newRequest request: URLRequest,
                completionHandler: @escaping (URLRequest?) -> Void) {
    // 从重定向响应中提取 Cookie
    if let cookies = HTTPCookie.cookies(
        withResponseHeaderFields: response.allHeaderFields as? [String: String] ?? [:],
        for: response.url ?? URL(string: "https://creator.douyin.com")!
    ) {
        // 保存到 Keychain
        self.saveCookies(cookies)
    }
    // 继续重定向（或传 nil 停止重定向）
    completionHandler(request)
}
```

### Cookie 有效性检测 & 用户信息获取

```
GET https://creator.douyin.com/web/api/media/user/info
Cookie: sessionid=xxx; sessionid_ss=xxx; ...

成功响应（Cookie 有效）:
{
  "status_code": 0,
  "user_info": {
    "uid": "12345678",
    "nickname": "美食探店号",
    "avatar_url": "https://...",
    "unique_id": "dyfx750s5c44",    // ← 这就是抖音号，用于账号匹配
    "short_id": "..."
  }
}

失败响应（Cookie 过期）:
HTTP 302 重定向到登录页 或 HTTP 401
```

**账号匹配**：`user_info.unique_id` 与飞书表格中的「抖音账号」列进行字符串匹配。

### 需要保存的抖音 Cookie 列表

登录成功后需保存以下关键 Cookie（域 `.douyin.com`）：

| Cookie 名 | 用途 | 重要程度 |
|-----------|------|---------|
| `sessionid` | 核心登录凭证 | 必须 |
| `sessionid_ss` | 备用登录凭证 | 必须 |
| `passport_csrf_token` | CSRF 防护 | 必须 |
| `ttwid` | 设备/浏览器标识 | 建议 |
| `msToken` | 请求验证 | 建议 |
| `odin_tt` | 设备标识 | 建议 |

> 建议：扫码登录后保存 **所有** 返回的 Cookie，而不是只保存已知的几个。避免因遗漏 Cookie 导致页面行为异常。

### 凭证存储规范

> **注意**：实际实现未使用系统 Keychain，而是使用本地文件存储（base64 编码），以避免系统 Keychain 每次访问弹出密码输入框。
> 存储路径：`~/Library/Application Support/com.menggang.douyin-uploader/secrets/`

| 文件名（Key） | 值 | 说明 |
|-------------|-----|------|
| `douyin.cookie.{unique_id}` | base64(JSON 序列化的 CookieDTO 数组) | 按抖音号隔离 |
| `douyin.userinfo.{unique_id}` | base64(JSON 序列化的用户信息) | 昵称、头像等 |
| `pat_{config_id}` | base64(PAT 字符串) | 按飞书配置隔离 |
| `appSecret_{config_id}` | base64(App Secret 字符串) | 按飞书配置隔离 |

封装在 `KeychainService`（名称保留但实现为文件 I/O，非系统 Keychain API）。

### 实际采用方案：Chrome for Testing + CDP

> **WKWebView 方案已弃用**（保留为 `DouyinPublishService` 备选代码）。实际发布使用 Chrome for Testing + Chrome DevTools Protocol (CDP)，原因：CDP 的 `DOM.setFileInputFiles` 可直接设置文件路径无需用户手势，账号间通过独立 Chrome 用户数据目录完美隔离。

#### Chrome 管理（ChromeManager）

```swift
// 1. 自动下载 Chrome for Testing（固定版本 131.0.6778.204）
// 存储路径：~/Library/Application Support/com.menggang.douyin-uploader/chrome/
// 自动识别架构：arm64 (M 系列) / x64 (Intel)

// 2. 启动 Chrome 进程
let (process, port) = try await chromeManager.launchChrome(accountId: "dyfx750s5c44")
// 参数：
//   --remote-debugging-port={port}
//   --user-data-dir={profileDir}  （按账号隔离）
//   --no-first-run
//   --disable-blink-features=AutomationControlled  （防检测）

// 3. 连接 CDP 客户端（WebSocket）
let cdp = CDPClient()
let wsURL = try await chromeManager.getPageWebSocketURL(port: port)
try await cdp.connect(wsURL: wsURL)
```

#### CDP 关键操作

| 操作 | CDP 命令 |
|------|---------|
| Cookie 注入 | `Network.setCookies` |
| 页面导航 | `Page.navigate` |
| DOM 操作 / JS 执行 | `Runtime.evaluate` |
| 文件上传 | `DOM.setFileInputFiles` — **无需用户手势** |
| 键盘输入 | `Input.insertText` + `Input.dispatchKeyEvent` |
| 等待元素 | 轮询 `Runtime.evaluate` 检测 DOM |
| 网络拦截 | `Network.enable` + 事件监听（用于音乐下载） |

#### WKWebView 保留用途

WKWebView 仍用于**扫码登录**（`QRCodeLoginView`）：
- 弹窗中加载抖音创作者中心，用户扫码
- 从 `WKHTTPCookieStore` 提取 Cookie
- 从 DOM 提取用户信息（昵称、头像）

### 防休眠与 App Nap

```swift
// IOKit 阻止系统休眠
var assertionID: IOPMAssertionID = 0
IOPMAssertionCreateWithName(
    kIOPMAssertionTypeNoIdleSleep as CFString,
    IOPMAssertionLevel(kIOPMAssertionLevelOn),
    "正在执行抖音发布任务" as CFString,
    &assertionID
)

// 禁用 App Nap
ProcessInfo.processInfo.beginActivity(
    options: .userInitiated,
    reason: "正在执行抖音发布任务"
)
```

> **以下为 WKWebView 备选方案的技术细节**。实际发布已改用 Chrome CDP，但 WKWebView 仍用于扫码登录（`QRCodeLoginView`），且 `DouyinPublishService` 作为备选方案保留。

4. **调试模式**：开发和排障时需要看到 WebView 内容。App 设置中预留「调试模式」开关，开启后将 off-screen 窗口移动到可见位置。

5. **WKWebView 与 URLSession Cookie 隔离**：两者使用独立的 Cookie 存储。扫码登录获取的 Cookie 需要同时存入：
   - `URLSession` 的 `HTTPCookieStorage` — 用于 Cookie 有效性检测
   - `WKHTTPCookieStore` — 用于 WKWebView 中的发布操作

6. **Cookie 注入竞态条件**：`setCookie()` 是异步操作，必须在 `completionHandler` 中再加载页面：
```swift
let group = DispatchGroup()
for cookie in cookies {
    group.enter()
    cookieStore.setCookie(cookie) { group.leave() }
}
group.notify(queue: .main) {
    webView.load(request) // 确保 cookie 已写入
}
```

7. **内存管理和实例生命周期**：
   - 每个 WKWebView 实例消耗约 100~200MB 内存
   - **建议每个账号创建新实例**：切换账号时销毁旧 WKWebView，创建新实例。这样可以避免 Cookie、LocalStorage、IndexedDB 等缓存残留导致的账号串扰问题
   - 创建新实例时使用 `WKWebsiteDataStore.nonPersistent()`（非持久化存储），确保实例销毁后数据完全清除

8. **User-Agent 设置**：WKWebView 默认 UA 与 Safari 略有不同，必须自定义为标准浏览器 UA：
```swift
webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
```

9. **Web Content Process 崩溃处理**：WKWebView 使用独立进程渲染网页，如果抖音页面 JS 出错导致进程崩溃，需要处理恢复：
```swift
func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    // 进程崩溃了，重新加载页面
    webView.reload()
    // 日志记录
    logger.warning("WKWebView 进程崩溃，正在重新加载")
}
```

10. **iframe 问题**：抖音页面的上传区域可能在 iframe 中。WKWebView 的 `evaluateJavaScript` 只能操作主 frame，不能直接访问跨域 iframe。如果发现上传组件在 iframe 中，需要通过 `WKFrameInfo` 或用 `WKUserScript` 注入到所有 frames（`forMainFrameOnly: false`）。

11. **WKUserScript 注入时机**：需要注入两类脚本：
   - `atDocumentStart`：防自动化检测（如覆盖 `navigator.webdriver`）、全局对象拦截
   - `atDocumentEnd`：DOM 操作工具函数（`waitForElement` 等）、发布流程自动化脚本
   - 两者都应设置 `forMainFrameOnly: false`（以防上传组件在 iframe 中）

12. **切换账号时清除 Cookie**：串行执行中切换到下一个账号时，必须先清除 WKWebView 中上一个账号的所有 Cookie，再注入新账号的 Cookie：
```swift
// 清除所有 Cookie
let dataStore = webView.configuration.websiteDataStore
let cookies = await dataStore.httpCookieStore.allCookies()
for cookie in cookies {
    await dataStore.httpCookieStore.deleteCookie(cookie)
}
// 然后注入新账号 Cookie
```

13. **WKWebView delegate 与 async/await 桥接**：WKWebView 的 delegate 方法（如 `didFinish`、`runOpenPanel`）是回调式的，需要桥接到 Swift async/await：
```swift
func waitForNavigation() async {
    await withCheckedContinuation { continuation in
        self.navigationContinuation = continuation
    }
}

// 在 delegate 中 resume
func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    navigationContinuation?.resume()
    navigationContinuation = nil
}
```

14. **evaluateJavaScript 错误处理**：`evaluateJavaScript` 的回调可能返回错误（如 JS 语法错误、DOM 元素不存在等），需在每次调用时处理：
```swift
webView.evaluateJavaScript(script) { result, error in
    if let error = error {
        logger.error("JS 执行失败: \(error.localizedDescription)")
        // 标记当前任务失败
    }
}
// 或使用 async 版本 (macOS 12+)
do {
    let result = try await webView.evaluateJavaScript(script)
} catch {
    logger.error("JS 执行失败: \(error)")
}
```

15. **React/Vue 组件状态同步**：抖音页面使用前端框架（React），直接修改 DOM input 的 value 不会触发框架的状态更新。需要通过触发 `InputEvent` 等原生事件来同步：
```javascript
// 设置输入值并触发 React 状态更新
function setInputValue(element, value) {
    const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
        window.HTMLTextAreaElement.prototype, 'value'
    ).set;
    nativeInputValueSetter.call(element, value);
    element.dispatchEvent(new Event('input', { bubbles: true }));
}
```

### JS ↔ Swift 双向通信方案

**Swift → JS**：通过 `evaluateJavaScript()` 注入执行

**JS → Swift**：通过 `WKScriptMessageHandler` 回调

```swift
// 1. 注册消息处理器
let userContentController = config.userContentController
userContentController.add(self, name: "publishResult")

// 2. JS 中发送消息到 Swift
// window.webkit.messageHandlers.publishResult.postMessage({
//     status: "success",
//     message: "发布成功"
// });

// 3. Swift 中接收消息
func userContentController(_ userContentController: WKUserContentController,
                           didReceive message: WKScriptMessage) {
    if message.name == "publishResult" {
        let body = message.body as? [String: Any]
        // 处理发布结果
    }
}
```

**典型通信场景**：
- 等待元素出现 → JS `setInterval` 轮询 DOM → 找到后 `postMessage` 通知 Swift
- 等待上传完成 → JS 监听进度条变化 → 完成后 `postMessage` 通知 Swift
- 获取发布结果 → JS 监听页面 URL 变化或成功提示出现 → `postMessage` 通知 Swift

### 等待元素出现 — 通用 JS 工具函数

这是 WKWebView 自动化中最核心的辅助函数，几乎每一步操作都需要：

```javascript
// 注入到 WKWebView 中的通用等待函数
function waitForElement(selector, timeout = 30000) {
    return new Promise((resolve, reject) => {
        const el = document.querySelector(selector);
        if (el) { resolve(el); return; }

        const observer = new MutationObserver(() => {
            const el = document.querySelector(selector);
            if (el) {
                observer.disconnect();
                clearTimeout(timer);
                resolve(el);
            }
        });

        observer.observe(document.body, { childList: true, subtree: true });

        const timer = setTimeout(() => {
            observer.disconnect();
            // 通知 Swift 超时
            window.webkit.messageHandlers.error.postMessage({
                type: 'timeout',
                selector: selector,
                // 输出当前页面状态，便于调试
                bodyHTML: document.body.innerHTML.substring(0, 500)
            });
            reject(new Error('等待元素超时: ' + selector));
        }, timeout);
    });
}

// 使用示例
waitForElement('.upload-btn').then(btn => btn.click());
```

Swift 端调用方式：
```swift
// 先注入工具函数（页面加载时通过 WKUserScript 注入）
// 然后执行等待操作
webView.evaluateJavaScript("""
    waitForElement('\(selector)').then(el => {
        el.click();
        window.webkit.messageHandlers.stepDone.postMessage('upload_clicked');
    }).catch(err => {
        window.webkit.messageHandlers.error.postMessage(err.message);
    });
""")
```

### 文件上传拦截详解（WKWebView 备选方案，已弃用）

> **实际采用 CDP 方案**：通过 `DOM.setFileInputFiles` 直接设置文件路径，完全绕过用户手势限制。以下 WKWebView 方案仅作技术备忘。

```swift
// WKUIDelegate 方法，当页面触发 <input type="file"> 时调用
func webView(_ webView: WKWebView,
             runOpenPanelWith parameters: WKOpenPanelParameters,
             initiatedByFrame frame: WKFrameInfo,
             completionHandler: @escaping ([URL]?) -> Void) {
    // 不弹出系统文件选择器，直接返回预设的文件路径
    completionHandler(self.pendingUploadFiles)
}
```

### 文件上传的用户手势限制（风险点）

**问题**：WebKit 对 `<input type="file">` 的 `.click()` 有用户手势要求。如果通过 `evaluateJavaScript("input.click()")` 调用且没有用户手势上下文，WebKit 可能拒绝触发文件选择（即 `runOpenPanel` 不会被调用）。

**应对方案（按优先级）**：

1. **方案 A：注入用户手势上下文**
   通过 `WKUserScript` 在页面加载时注入 JS，监听特定事件（如页面的按钮点击），在事件处理函数中调用 `input.click()`，这样就有了用户手势上下文。

2. **方案 B：直接拦截文件 API**
   在页面加载前注入 JS 脚本，拦截抖音页面的文件上传逻辑。例如覆盖 `FormData.append()` 或 `XMLHttpRequest.send()`，直接通过 JS Bridge 将文件数据传入。

3. **方案 C：模拟拖拽上传**
   抖音创作者中心支持拖拽上传。通过 JS 构造 `DragEvent` 和 `DataTransfer` 对象，模拟文件拖入上传区域：
   ```javascript
   const dt = new DataTransfer();
   dt.items.add(file);
   const dropEvent = new DragEvent('drop', { dataTransfer: dt, bubbles: true });
   uploadArea.dispatchEvent(dropEvent);
   ```
   > 注意：`DataTransfer` 构造也可能受安全限制，需要实际测试。

4. **方案 D（保底）：使用可见但最小化的窗口**
   将 WKWebView 放在一个可见但被遮挡/最小化的窗口中，通过 `NSWindow.performMiniaturize` 或设置窗口 level 为最低。

> **结论**：文件上传风险已通过改用 Chrome CDP 的 `DOM.setFileInputFiles` 完全解决，无需以上备选方案。

### 图文 vs 视频发布的页面差异

| 操作 | 视频发布 | 图文发布 |
|------|---------|---------|
| 入口 URL | `creator.douyin.com/creator-micro/content/post/video?enter_from=publish_page` | `creator.douyin.com/creator-micro/content/post/image?...&media_type=image&ttype=new` |
| 上传控件 | 视频文件 input | 图片文件 input（支持多选） |
| 等待处理 | 视频转码耗时较长 | 图片处理较快 |
| 封面 | 打开封面选择弹窗 → 选择推荐封面 → 确认 | 不适用 |
| 标题字段 | **无独立标题**，文案即描述 | 有独立标题输入框（待验证） |
| 文案/描述 | 描述输入框（文案 + #话题） | 描述输入框（文案 + #话题） |
| **音乐入口** | 点击「添加音乐」（`.text-JK4gL5`） | 点击「选择音乐」（`.action-Q1y01k`） |
| **音乐面板** | 右侧弹出相同的选择音乐面板 | 右侧弹出相同的选择音乐面板 |

> 注意：以上 URL 和选择器需要在开发时实际抓取验证，抖音页面结构可能更新。

### 音乐融合技术实现

> **实际方案**：不在抖音发布页面内选择音乐，而是**下载音乐文件 → 合并到视频中 → 上传合并后的视频**。仅视频作品支持。

**流程**（`MusicDownloader` + `AudioVideoMerger`）：

```
1. MusicDownloader：通过 CDP 在抖音文章发布页搜索并下载音乐
   a. 启动独立 Chrome 实例，打开文章发布页
      https://creator.douyin.com/creator-micro/content/post/article?...
   b. CDP 启用 Network 域，注册响应监听
   c. 点击「选择音乐」按钮
   d. 等待搜索框出现，输入音乐名称
   e. 点击搜索结果（触发音频加载请求）
   f. 通过 CDP Network 事件拦截音频 URL：
      - CDN 域名匹配：douyinstatic.com/obj/tos-cn-* 或 bytecdn.cn
      - MIME 类型匹配：含 "audio" 或 "octet-stream"
   g. 下载音频到本地临时目录

2. AudioVideoMerger：AVFoundation 合并视频+音乐
   a. 加载视频和音乐 AVAsset
   b. 创建 AVMutableComposition
   c. 添加视频轨道（含原声，音量 100%）
   d. 添加音乐轨道（音量 30%，循环/截断到视频长度）
   e. 导出合并视频（AVAssetExportSession）
   f. 输出路径：/var/folders/.../T/douyin_merged/

3. 上传合并后的视频文件（而非原始视频）
```

**注意事项**：
- 音乐融合失败**不应阻断发布流程**，回退上传原始视频并记录警告日志
- 背景音乐音量默认 30%，原声保持 100%
- 音乐时长不足则循环播放，超出则截断到视频长度
- 文章发布页的「选择音乐」比视频发布页的音乐入口更稳定，因此专门用文章页来下载音乐
- 选择器建议使用模糊匹配模式（如 `button[class*="apply-btn-"]`）或文字内容匹配，避免 hash 后缀变化导致失效

### 发布结果确认

点击"发布"按钮后，需要判断是否真正发布成功。可能的判断方式：

1. **页面跳转**：发布成功后页面通常跳转到"作品管理"或"发布成功"页面，通过 `WKNavigationDelegate` 监听 URL 变化
2. **DOM 变化**：页面出现"发布成功"等提示文字，通过 JS 轮询检测
3. **超时兜底**：如果 30 秒内既没有跳转也没有成功提示 → 判断为未知状态，标记失败

```javascript
// 发布结果监听脚本
function watchPublishResult(timeout = 30000) {
    return new Promise((resolve, reject) => {
        // 方式1：监听 URL 变化
        const originalUrl = location.href;
        const urlChecker = setInterval(() => {
            if (location.href !== originalUrl) {
                clearInterval(urlChecker);
                clearTimeout(timer);
                resolve({ method: 'url_change', url: location.href });
            }
        }, 500);

        // 方式2：监听成功提示 DOM
        const observer = new MutationObserver(() => {
            if (document.body.innerText.includes('发布成功') ||
                document.body.innerText.includes('作品已发布')) {
                observer.disconnect();
                clearInterval(urlChecker);
                clearTimeout(timer);
                resolve({ method: 'dom_text', text: '发布成功' });
            }
        });
        observer.observe(document.body, { childList: true, subtree: true });

        // 超时兜底
        const timer = setTimeout(() => {
            observer.disconnect();
            clearInterval(urlChecker);
            reject(new Error('发布结果确认超时'));
        }, timeout);
    });
}
```

> 具体的成功判断条件（URL 模式、DOM 文本）需要在 Phase 0 抓取确认。

### 定时发布实现

抖音创作者中心支持定时发布，UI 交互为：
1. 发布页面有"立即发布"和"定时发布"两个单选按钮
2. 选择"定时发布"后出现日期时间输入框（Semi DatePicker 组件）
3. 已验证的自动化流程：

```swift
// 1. 点击"定时发布"单选按钮（遍历 DOM 查找文本匹配）
document.querySelectorAll('.semi-radio, [class*="radio"], span, label, div')
// → 找到 textContent === '定时发布' 的元素并 click()

// 2. 点击日期输入框，焦点 + 全选
var input = document.querySelector('input[placeholder*="日期"], input[format*="yyyy"]');
input.click(); input.focus(); input.select();

// 3. 通过 CDP Input.insertText 直接键入时间字符串（如 "2026-03-28 19:00"）
// select() 全选后 insertText 会替换已有内容

// 4. Enter 确认
```

> **关键发现**：日期输入框不能用逐字符输入或先删后填的方式，必须用 `input.select()` 全选后直接 `insertText` 一次性键入完整时间字符串覆盖，否则会出现内容追加而非替换的问题。

### 关键开源参考

| 项目 | Stars | 技术栈 | 参考价值 |
|------|-------|--------|---------|
| **social-auto-upload** | 2000+ | Python + Playwright | 发布流程逻辑、页面选择器、定时发布实现 |
| MediaCrawler | 10000+ | Python + Playwright | 扫码登录流程、Cookie 管理 |
| f2 | - | Python | 逆向签名算法（仅参考，不采用） |

**重点参考 social-auto-upload**：虽然技术栈不同（Python vs Swift），但其发布流程逻辑、CSS 选择器、等待策略可直接参考转换为 JS 注入脚本。

---

## 三、风险评估

| 风险 | 影响 | 风险等级 | 缓解措施 |
|------|------|---------|---------|
| ~~文件上传用户手势限制~~ | ~~runOpenPanel 可能不触发~~ | ~~已解决~~ | 已改用 Chrome CDP 的 `DOM.setFileInputFiles`，无需用户手势 |
| 抖音页面结构变更 | CSS 选择器失效 | 高 | 优先文字内容匹配，class 名辅助；选择器集中在 CDPPublishService 中 |
| 抖音风控检测 | 账号被限制或封禁 | 中 | 串行执行、随机间隔、模拟正常操作节奏、`--disable-blink-features=AutomationControlled` |
| Chrome 进程管理 | 进程残留或端口冲突 | 低 | 启动前杀掉旧进程，自动选择可用端口 |
| Cookie 频繁过期 | 需要反复扫码 | 中 | 记录有效期规律，提前提醒用户 |
| 大视频上传不稳定 | 上传中断或超时 | 中 | 合理超时、失败标记、支持重试 |
| 飞书 PAT 不可用 | 企业未开放 | 低 | 自建应用方式作为备选 |
| App Nap 节流 | 长时间任务被系统暂停 | 低 | `beginActivity` 禁用 App Nap |

### 防风控策略

- 每条任务之间随机等待 5~15 秒
- 同一账号连续发布不超过 10 条后强制等待 5 分钟
- JS 注入操作之间加入随机延迟（0.5~2 秒），模拟人工操作节奏
- User-Agent 保持与正常 Safari/Chrome 一致

### 休眠防护

执行任务期间需要阻止 Mac 休眠（否则网络连接断开、WKWebView 被冻结）：

```swift
// 使用 IOPMAssertion 阻止休眠
var assertionID: IOPMAssertionID = 0
IOPMAssertionCreateWithName(
    kIOPMAssertionTypeNoIdleSleep as CFString,
    IOPMAssertionLevel(kIOPMAssertionLevelOn),
    "正在执行抖音发布任务" as CFString,
    &assertionID
)
// 任务完成后释放
IOPMAssertionRelease(assertionID)
```

结合 `ProcessInfo.beginActivity` 同时防护 App Nap 和系统休眠。

---

## 四、飞书 URL 解析规则

飞书多维表格 URL 格式示例：
```
# 国内版（飞书）
https://example.feishu.cn/base/VwGhbxxxxxxx?table=tblYyyyyyyy&view=vewZzzzzz

# 国际版（Lark）
https://example.larksuite.com/base/VwGhbxxxxxxx?table=tblYyyyyyyy&view=vewZzzzzz
```

两种格式的解析规则相同，仅域名不同。App 需根据域名自动识别 API Base URL。

解析规则：
- **App Token**：`/base/` 后面的路径段 → `VwGhbxxxxxxx`
- **Table ID**：查询参数 `table` 的值 → `tblYyyyyyyy`
- **View ID**：查询参数 `view` 的值（可选，不使用）

正则提取：
```swift
// 提取 app_token
let appTokenPattern = #"/base/([A-Za-z0-9]+)"#
// 提取 table_id
let tableIdPattern = #"[?&]table=([A-Za-z0-9]+)"#
```

---

## 五、CSS 选择器管理

> **实际实现**：选择器已硬编码在 `CDPPublishService.swift` 中，未使用独立的 `selectors.json` 文件。

### 当前使用的选择器策略

选择器采用**文字内容匹配优先、CSS class 辅助**的策略，避免 hash 后缀变化导致失效：

```swift
// 示例：CDPPublishService 中的选择器使用方式

// 文案编辑器（CSS class 稳定）
".zone-container[contenteditable='true']"

// 定时发布输入框（placeholder 匹配）
"input[placeholder*='日期'], input[format*='yyyy']"

// 定时发布按钮（遍历 DOM 文字匹配）
var radios = document.querySelectorAll('.semi-radio, [class*="radio"], span, label, div');
// → 找到 textContent === '定时发布' 的元素

// 发布按钮（遍历按钮文字匹配）
var buttons = document.querySelectorAll('button');
// → 找到 textContent 含 '发布' 的按钮
```

### 关键 URL（已验证）

| 用途 | URL |
|------|-----|
| 视频发布页 | `https://creator.douyin.com/creator-micro/content/post/video?enter_from=publish_page` |
| 图文发布页 | `https://creator.douyin.com/creator-micro/content/post/image?default_tab=3&enter_from=publish_page&media_type=image&ttype=new` |
| 发布成功判断 | URL 含 `creator-micro/content/manage` |
| 文章发布页（音乐下载用） | `https://creator.douyin.com/creator-micro/content/post/article?...` |

### 选择器更新策略

- 目前选择器硬编码在代码中，更新需修改 `CDPPublishService.swift` 并重新构建
- 未来可抽取为独立配置文件以支持热更新（v2 考虑）
- 抖音创作者中心使用 **Semi Design** UI 库（字节跳动），选择器多含 `semi-` 前缀

---

## 六、建议代码架构

```
DouyinUploader/
├── App/
│   └── DouyinUploaderApp.swift          # App 入口
├── Models/
│   ├── FeishuConfig.swift               # 飞书配置模型
│   ├── DouyinAccount.swift              # 抖音账号模型
│   ├── PublishTask.swift                # 发布任务模型（含话题标签、音乐名称）
│   ├── PublishStatus.swift              # 发布状态枚举（状态机）
│   ├── ExecutionLog.swift               # 执行日志模型
│   ├── FeishuAttachment.swift           # 飞书附件模型（fileToken, name, type, size）
│   ├── MediaType.swift                  # 媒体类型枚举 + 验证
│   └── AppSettings.swift               # 全局设置模型
├── Services/
│   ├── Feishu/
│   │   ├── FeishuAPI.swift              # 飞书 API 封装（读取/回写/附件下载）
│   │   ├── FeishuAuthManager.swift      # PAT / tenant_token 认证管理
│   │   └── FeishuURLParser.swift        # URL 解析 + 话题标签解析
│   ├── Chrome/
│   │   ├── ChromeManager.swift          # Chrome for Testing 下载/启动/端口管理
│   │   ├── CDPClient.swift              # CDP WebSocket 客户端（命令发送/事件监听）
│   │   ├── CDPPublishService.swift      # 发布执行（Chrome CDP 自动化，主方案）
│   │   └── MusicDownloader.swift        # CDP 网络拦截下载音乐
│   ├── Douyin/
│   │   ├── DouyinLoginService.swift     # 扫码登录
│   │   ├── DouyinPublishService.swift   # 发布执行（WKWebView，备选方案）
│   │   ├── DouyinCookieManager.swift    # Cookie 序列化/反序列化
│   │   └── WebViewManager.swift         # WKWebView 封装（登录+备选发布）
│   ├── KeychainService.swift            # 凭证存储（本地文件 base64，非系统 Keychain）
│   ├── AccountStore.swift               # 账号列表持久化
│   ├── ConfigStore.swift                # 飞书配置持久化
│   ├── LogStore.swift                   # 执行日志持久化
│   ├── SettingsManager.swift            # 设置持久化
│   ├── AudioVideoMerger.swift           # 视频+音乐合并（AVFoundation）
│   ├── NetworkMonitor.swift             # 网络状态监测
│   └── NotificationService.swift        # 系统通知
├── ViewModels/
│   ├── FeishuConfigViewModel.swift      # 飞书配置页逻辑
│   ├── AccountViewModel.swift           # 账号管理页逻辑
│   ├── ExecutionViewModel.swift         # 执行发布页逻辑（核心）
│   └── HistoryViewModel.swift           # 历史记录页逻辑
├── Views/
│   ├── Sidebar/
│   │   └── SidebarView.swift            # 侧边栏
│   ├── FeishuConfig/
│   │   ├── FeishuConfigListView.swift
│   │   └── FeishuConfigEditView.swift
│   ├── Account/
│   │   ├── AccountListView.swift
│   │   └── QRCodeLoginView.swift
│   ├── Execution/
│   │   ├── ExecutionView.swift          # 执行主页
│   │   ├── TaskOverviewView.swift       # 执行概览
│   │   ├── TaskPreviewView.swift        # 任务预览列表
│   │   ├── ProgressView.swift           # 进度 + 日志
│   │   └── SummaryView.swift            # 完成总结
│   ├── History/
│   │   └── HistoryView.swift
│   ├── Settings/
│   │   └── SettingsView.swift
│   └── Onboarding/
│       └── OnboardingView.swift         # 首次使用引导
├── Resources/
│   ├── （selectors.json 已移除，选择器硬编码在 CDPPublishService 中）
│   └── Assets.xcassets
└── JS/
    ├── douyin_video_publish.js           # 视频发布自动化脚本
    ├── douyin_image_publish.js           # 图文发布自动化脚本
    ├── （douyin_music_select.js 已移除，音乐下载改用 MusicDownloader CDP 方案）
    └── douyin_helpers.js                 # 通用 JS 工具函数
```

**关键设计原则**：
- MVVM 架构：Model → Service → ViewModel → View
- Service 层使用 async/await，ViewModel 用 `ObservableObject` + `@Published`（macOS 13 兼容；`@Observable` 需 macOS 14+）
- JS 脚本作为独立文件管理，不硬编码在 Swift 中（Bundle.module 加载）
- 主发布方案使用 `CDPPublishService`（Chrome CDP），备选方案保留 `DouyinPublishService`（WKWebView）
- 音乐通过 `MusicDownloader`（CDP 网络拦截）下载后，`AudioVideoMerger`（AVFoundation）合并到视频中

**SwiftUI 布局注意点**：
- 主窗口结构：`VStack { NavigationSplitView { ... } StatusBar() }`
- `NavigationSplitView` 不支持底部状态栏，需要外层包一个 `VStack`
- 状态栏使用独立的 `StatusBarViewModel`（`@EnvironmentObject`），各页面都可更新
- 执行发布页状态管理：用 `enum ExecutionState { case idle, loading, overview, running, paused, networkError, completed }` 枚举控制，同一 View 中条件渲染（`switch state`），不用 NavigationStack
- 日志实时滚动：`ScrollViewReader` + `.onChange(of: logs.count) { scrollTo(lastID) }`
- 二维码弹窗：`.sheet(isPresented:)` modifier，传入 `QRCodeLoginView`

---

## 七、App 本地存储路径汇总

| 数据 | 存储位置 | 格式 |
|------|---------|------|
| 飞书配置（非敏感） | `~/Library/Application Support/com.menggang.douyin-uploader/configs.json` | JSON |
| 账号列表（非敏感） | `~/Library/Application Support/com.menggang.douyin-uploader/accounts.json` | JSON |
| 设置项 | `~/Library/Application Support/com.menggang.douyin-uploader/settings.json` | JSON |
| 执行日志 | `~/Library/Application Support/com.menggang.douyin-uploader/logs/{timestamp}_{logId}.json` | JSON |
| 敏感凭证（Cookie/PAT/Secret） | `~/Library/Application Support/com.menggang.douyin-uploader/secrets/` | base64 编码文件 |
| Chrome for Testing | `~/Library/Application Support/com.menggang.douyin-uploader/chrome/` | 二进制 |
| Chrome 用户数据（按账号） | `~/Library/Application Support/com.menggang.douyin-uploader/chrome-profiles/{accountId}/` | 浏览器数据 |
| 临时下载素材 | `NSTemporaryDirectory()/douyin_upload/` | 文件 |
| 临时合并视频 | `/var/folders/.../T/douyin_merged/` | 视频文件 |

> App 首次启动时需自动创建 Application Support 子目录和 logs 子目录（`FileManager.default.createDirectory`）。

---

## 八、日志文件格式

### 存储位置

```
~/Library/Application Support/com.menggang.douyin-uploader/logs/
├── 2026-03-25_103201.json     # 执行日志（按执行时间命名）
├── 2026-03-25_143500.json
└── ...
```

### 日志文件结构

```json
{
  "execution_id": "uuid",
  "started_at": "2026-03-25T10:32:01+08:00",
  "finished_at": "2026-03-25T10:37:33+08:00",
  "feishu_config": "运营表格-3月",
  "total": 12,
  "success": 10,
  "failed": 2,
  "duration_seconds": 332,
  "entries": [
    {
      "timestamp": "2026-03-25T10:32:01+08:00",
      "level": "info",
      "message": "读取任务数据完成，共 12 条"
    },
    {
      "timestamp": "2026-03-25T10:32:03+08:00",
      "level": "info",
      "task_index": 1,
      "task_type": "image",
      "account": "dyfx750s5c44",
      "message": "下载素材中..."
    },
    {
      "timestamp": "2026-03-25T10:32:46+08:00",
      "level": "info",
      "task_index": 1,
      "task_type": "image",
      "account": "dyfx750s5c44",
      "message": "搜索音乐「草莓不能 创作的原声」",
      "music_name": "草莓不能 创作的原声",
      "music_status": "found"
    }
  ]
}
```

### 日志级别

| 级别 | 说明 |
|------|------|
| `info` | 正常操作步骤 |
| `success` | 任务发布成功 |
| `error` | 任务失败 |
| `warning` | 非致命问题（如飞书回写失败、音乐下载失败/超时、合并失败） |

**可选字段**（音乐相关 entry 额外携带）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `music_name` | string | 待搜索的音乐名称（仅音乐操作相关日志） |
| `music_status` | string | `found` / `not_found` / `timeout`（搜索结果状态） |

---

## 九、术语定义

| 术语 | 定义 |
|------|------|
| **发布状态** | 飞书表格中的单选列，有 4 种值：允许发布、发布中、已发布、发布失败 |
| **孤儿任务** | 状态停留在「发布中」的任务，通常因 App 异常退出导致。下次执行时自动纳入重试 |
| **off-screen 窗口** | 位于屏幕外（如坐标 -10000,-10000）的 NSWindow，WKWebView 挂载其上以确保 JS 正常执行（仅扫码登录使用） |
| **CDP** | Chrome DevTools Protocol，通过 WebSocket 与 Chrome 浏览器通信的协议，用于自动化控制浏览器（主发布方案） |
| **Chrome for Testing** | Google 提供的专用于自动化测试的 Chrome 版本，固定版本号 131.0.6778.204 |
| **Spike Test** | 技术验证实验，在正式开发前验证核心技术点的可行性 |
| **选择器（Selector）** | CSS 选择器字符串，用于在抖音页面中定位 DOM 元素（如上传按钮、输入框等） |
| **PAT** | Personal Access Token，飞书个人访问令牌 |
| **tenant_access_token** | 飞书自建应用的应用级访问令牌，有效期 2 小时 |
| **Semi Design** | 字节跳动开源的 UI 组件库（React），抖音创作者中心页面使用，选择器多含 `semi-` 前缀 |
| **音乐融合** | 通过 CDP 下载音乐文件，用 AVFoundation 合并到视频中后上传（替代了之前的页面内音乐选择方案） |
| **Hash 后缀** | CSS class 名中由构建工具自动生成的随机字符（如 `apply-btn-LUPP0D`），可能随页面更新变化 |

---

> 相关文档：[PRD 需求文档](./PRD.md)
