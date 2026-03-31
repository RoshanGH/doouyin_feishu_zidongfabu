# 抖音发布助手 — AI 驱动重构设计文档

> 状态：设计中 | 创建日期：2026-03-31

## 一、为什么要重构

### 现状痛点

当前发布流程依赖 **40+ 处硬编码的页面结构匹配**（CSS 选择器、文字匹配、URL 判断），任何一处失效都会导致发布失败：

| 问题类型 | 数量 | 例子 |
|---------|------|------|
| 硬编码文字匹配 | 8+ 处 | "放弃"、"完成"、"发布"、"选择封面"、"发布图文" |
| CSS 动态类名 | 4 处 | `action-Q1y01k`、`card-container-*`、`apply-btn-*` |
| 验证码关键词 | 8 个 | "滑动"、"拼图"、"验证码"、"请完成验证"... |
| placeholder 匹配 | 2 处 | `input[placeholder*="标题"]`、`input[placeholder*="搜索音乐"]` |
| contenteditable 定位 | 1 处 | `.zone-container[contenteditable="true"]` |

**实际遇到的问题**：
- 不同账号看到不同的页面样式（A/B 测试）
- 随机弹出活动弹窗、促销提示、新功能引导
- 抖音前端频繁更新，class 名带 hash 后缀每次构建都变
- "选择封面"按钮在不同分辨率/账号下结构不同
- 新类型的验证码无法识别

### 核心结论

**靠硬编码选择器维护不下去**。需要让 AI 来"看"页面，理解当前状态，自己决定下一步操作。

## 二、AI 驱动架构设计

### 核心思路

**截图 → AI 理解 → 决策 → CDP 执行 → 截图验证**

不再依赖 CSS 选择器和文字匹配，而是：
1. 对当前页面截图
2. 发送截图给 AI（Claude Vision），附带当前任务上下文
3. AI 返回下一步操作指令（点击坐标、输入文本、等待等）
4. 通过 CDP 执行操作
5. 再次截图验证操作是否成功

### 架构图

```
┌─────────────────────────────────────────────────┐
│                 ExecutionEngine                   │
│                                                   │
│  ┌───────────┐    ┌──────────┐    ┌───────────┐  │
│  │ TaskQueue  │───>│ AIAgent  │───>│ CDPDriver │  │
│  │ (飞书任务) │    │ (决策层)  │    │ (执行层)  │  │
│  └───────────┘    └──────────┘    └───────────┘  │
│                         │                         │
│                    ┌────┴────┐                    │
│                    │ Vision  │                    │
│                    │ (截图)   │                    │
│                    └─────────┘                    │
└─────────────────────────────────────────────────┘
```

### 三层分离

| 层 | 职责 | 实现 |
|----|------|------|
| **决策层 (AIAgent)** | 看截图，理解页面状态，决定下一步操作 | Claude Vision API |
| **执行层 (CDPDriver)** | 执行具体操作（点击、输入、截图、导航） | Chrome CDP 协议 |
| **编排层 (TaskEngine)** | 管理任务队列、重试、状态机 | Swift 本地逻辑 |

## 三、AIAgent 设计

### 3.1 工作流程

```
1. CDPDriver.screenshot() → 获取当前页面截图（PNG）
2. AIAgent.analyze(screenshot, context) → 发送给 Claude Vision
   - context 包含：当前任务信息（文案、话题、音乐、定时时间）、当前步骤、历史操作
3. Claude 返回 JSON 格式的操作指令：
   {
     "status": "need_action",        // need_action / completed / error / waiting_user
     "description": "页面显示上传界面，需要上传视频文件",
     "action": {
       "type": "upload_file",        // click / type / upload_file / wait / scroll / press_key
       "selector": "input[type=file]",  // 可选，AI 识别出的选择器
       "coordinates": [640, 400],    // 可选，点击坐标
       "text": "",                   // 可选，输入文本
       "key": ""                     // 可选，按键
     },
     "next_step": "等待视频上传完成"
   }
4. CDPDriver 执行操作
5. 等待页面变化 → 回到步骤 1
```

### 3.2 Prompt 设计

```
你是一个抖音创作者中心的自动化操作助手。

当前任务：
- 类型：视频发布
- 文案：{content}
- 话题：{tags}
- 音乐：{musicName}
- 定时：{scheduleTime}
- 当前步骤：{currentStep}

请看这张页面截图，告诉我：
1. 当前页面处于什么状态（上传页/填写信息页/发布成功/登录页/验证码/弹窗）
2. 需要执行什么操作
3. 如果有弹窗或遮挡层，先处理它

返回 JSON 格式的操作指令。
```

### 3.3 AI 能处理的场景（现有方案做不到的）

| 场景 | 现有方案 | AI 方案 |
|------|---------|---------|
| 随机活动弹窗 | 无法处理，卡住 | AI 识别弹窗，找到关闭按钮点击 |
| A/B 测试不同布局 | 选择器失效 | AI 理解页面语义，不依赖选择器 |
| 新类型验证码 | 无法识别 | AI 识别验证码类型，提醒用户 |
| 文案改动 | "放弃"改成"取消"就失效 | AI 理解按钮语义 |
| 未知弹窗 | 不处理 | AI 判断是否需要关闭 |
| 封面选择 | 坐标点击不稳定 | AI 识别封面卡片位置 |
| 上传进度判断 | URL 变化检测 | AI 看截图判断是否上传完成 |

### 3.4 操作类型定义

```swift
enum AIAction {
    case click(x: Int, y: Int)           // 点击坐标
    case type(text: String)              // 键盘输入
    case pressKey(key: String)           // 按键（Enter、Tab、Escape）
    case uploadFile(paths: [String])     // 上传文件
    case scroll(direction: String, amount: Int)  // 滚动
    case wait(seconds: Int)              // 等待
    case screenshot                       // 再截一次图（验证）
    case waitForUser(message: String)    // 需要用户手动操作（验证码）
    case completed(message: String)      // 当前步骤完成
    case error(message: String)          // 出错
}
```

## 四、CDPDriver 设计

### 4.1 核心能力

CDPDriver 只做**执行**，不做决策。提供以下原子操作：

```swift
protocol CDPDriver {
    // 截图
    func screenshot() async throws -> Data  // PNG 图片数据

    // 点击
    func click(x: Int, y: Int) async throws

    // 输入
    func type(text: String) async throws
    func pressKey(_ key: String) async throws

    // 文件上传
    func uploadFiles(_ paths: [String]) async throws

    // 滚动
    func scroll(direction: String, amount: Int) async throws

    // 导航
    func navigate(to url: String) async throws
    func getCurrentURL() async throws -> String

    // Cookie
    func clearCookies() async throws
    func setCookies(_ cookies: [...]) async throws
    func getCookies(domain: String) async throws -> [...]
}
```

### 4.2 截图实现

通过 CDP `Page.captureScreenshot` 命令获取页面截图：

```swift
func screenshot() async throws -> Data {
    let result = try await cdp.send("Page.captureScreenshot", params: [
        "format": "png",
        "quality": 80
    ])
    guard let base64 = (result["result"] as? [String: Any])?["data"] as? String,
          let data = Data(base64Encoded: base64) else {
        throw CDPError.screenshotFailed
    }
    return data
}
```

## 五、TaskEngine 设计（编排层）

### 5.1 发布流程状态机

```
idle → uploading → filling_info → setting_cover → scheduling → publishing → completed
                                                                     ↓
                                                                  failed
任何状态 → popup_detected → (AI 处理弹窗) → 返回原状态
任何状态 → captcha_detected → waiting_user → 返回原状态
任何状态 → login_expired → failed
```

### 5.2 单条任务执行流程

```swift
func executeTask(_ task: PublishTask) async throws -> PublishResult {
    // 1. 导航到上传页
    try await driver.navigate(to: uploadURL)

    // 2. AI 驱动循环：截图 → 分析 → 执行 → 验证
    var maxSteps = 50  // 防止无限循环
    while maxSteps > 0 {
        maxSteps -= 1

        // 截图
        let screenshot = try await driver.screenshot()

        // AI 分析
        let action = try await agent.analyze(
            screenshot: screenshot,
            task: task,
            currentStep: currentStep,
            history: actionHistory
        )

        // 执行
        switch action {
        case .click(let x, let y):
            try await driver.click(x: x, y: y)
        case .type(let text):
            try await driver.type(text: text)
        case .uploadFile(let paths):
            try await driver.uploadFiles(paths)
        case .waitForUser(let message):
            // 三重提醒，等待用户手动操作
            await notifyUser(message)
            try await waitForUserCompletion()
        case .completed(let message):
            return PublishResult(success: true, message: message)
        case .error(let message):
            throw PublishError.aiFailed(message)
        default:
            break
        }

        // 等待页面变化
        try await Task.sleep(nanoseconds: 1_500_000_000)
    }

    throw PublishError.maxStepsExceeded
}
```

### 5.3 弹窗自动处理

AI 看到截图后会自动识别弹窗类型并给出操作：

- **活动弹窗**：AI 找到"关闭"/"×"按钮 → 点击关闭
- **新功能引导**：AI 找到"知道了"/"跳过"按钮 → 点击跳过
- **确认弹窗**：AI 根据上下文决定点"确认"还是"取消"
- **验证码**：AI 识别到验证码 → 返回 `waitForUser`
- **登录过期**：AI 看到登录页 → 返回 `error`

## 六、AI API 集成

### 6.1 API 配置

使用 OpenAI 兼容的转发服务，国内直连无需 VPN：

```
Base URL:  https://apicn.unifyllm.top/v1
API Key:   在设置页配置（存 secrets/ 目录）
模型:      claude-sonnet-4-6（推荐，视觉能力强、性价比高）
格式:      OpenAI chat/completions 兼容
```

### 6.2 API 调用（Swift 实现）

```swift
struct AIVisionService {
    let baseURL: String   // https://apicn.unifyllm.top/v1
    let apiKey: String
    let model: String     // claude-sonnet-4-6

    /// 发送截图给 AI，获取操作指令
    func analyze(screenshot: Data, prompt: String) async throws -> AIAction {
        let base64Image = screenshot.base64EncodedString()

        // OpenAI 兼容格式
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(base64Image)"
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        // POST {baseURL}/chat/completions
        // Headers: Authorization: Bearer {apiKey}
        // 解析返回的 JSON 操作指令
    }
}
```

### 6.3 设置页配置项

| 设置项 | 说明 | 默认值 |
|--------|------|--------|
| AI API 地址 | OpenAI 兼容的 API 转发地址 | `https://apicn.unifyllm.top/v1` |
| AI API Key | API 密钥 | （用户填写，存 secrets/） |
| AI 模型 | 使用的模型名称 | `claude-sonnet-4-6` |
| AI 模式 | 关闭 / 仅弹窗检测 / 完整 AI 驱动 | 仅弹窗检测 |

> API Key 存在 `secrets/ai_api_key`，和飞书 PAT 一样的存储方式。
> 同事使用时，管理员在每台电脑的设置页填入同一个 Key 即可。

### 6.4 成本估算

| 操作 | 截图次数 | Token 消耗 | 费用/条（估算） |
|------|---------|-----------|----------------|
| 视频发布（混合模式） | ~8 次 | ~20K tokens | ~$0.05 |
| 图文发布（混合模式） | ~6 次 | ~15K tokens | ~$0.04 |
| **日均 50 条** | | | **~$2.5/天** |

> 混合模式下 AI 只在需要时调用（弹窗检测、按钮定位），比纯 AI 模式便宜 50%。

### 6.5 优化策略

1. **本地规则优先**：URL 导航、文件上传、键盘输入等确定性操作不调 AI
2. **截图压缩**：降低分辨率（1280→640），JPEG 压缩到 60% 质量，减少 token
3. **页面状态缓存**：连续截图相似度 > 95% 时复用上次 AI 判断
4. **快速模型预筛**：用便宜的模型做状态分类，复杂场景再用 Sonnet

## 七、混合架构（推荐）

纯 AI 方案成本高、速度慢。推荐**混合架构**：简单确定性操作用代码，不确定的用 AI。

### 7.1 代码处理（快速、免费）

- URL 导航和等待
- Cookie 注入和管理
- 文件上传（CDP `setFileInputFiles`）
- 键盘输入（文案、话题标签）
- 定时时间填写

### 7.2 AI 处理（灵活、自适应）

- **弹窗检测和处理** — 截图后 AI 判断是否有弹窗，如何关闭
- **页面状态判断** — 当前是上传页/填写页/发布成功/异常状态
- **元素定位** — "选择封面"在哪里、"发布"按钮在哪里
- **验证码识别** — 是否出现验证码、是什么类型
- **异常恢复** — 页面不符合预期时，AI 决定如何恢复

### 7.3 混合流程示例

```
1. [代码] 导航到上传页
2. [AI]   截图 → 检查页面状态（是否有弹窗、是否正常）
3. [代码] 上传文件（CDP setFileInputFiles）
4. [代码] 等待 URL 变化（包含 "publish"）
5. [AI]   截图 → 确认进入了填写信息页（处理可能的弹窗）
6. [代码] 填写标题、文案、话题（键盘输入）
7. [AI]   截图 → 找到「选择封面」位置 → 返回坐标
8. [代码] CDP 鼠标点击坐标
9. [AI]   截图 → 确认封面弹窗打开 → 找到「完成」按钮 → 返回坐标
10. [代码] CDP 鼠标点击坐标
11. [AI]  截图 → 确认封面设置完成
12. [代码] 填写定时发布时间
13. [AI]  截图 → 找到「发布」按钮 → 返回坐标
14. [代码] CDP 鼠标点击坐标
15. [AI]  截图 → 确认发布成功（或失败）
```

## 八、配置和 API Key 管理

### 8.1 用户设置

在设置页新增"AI 配置"区域：

| 设置项 | 默认值 | 说明 |
|--------|--------|------|
| API 转发地址 | `https://apicn.unifyllm.top/v1` | OpenAI 兼容的 API 地址，国内直连 |
| API Key | （必填） | 管理员配置，同事共用 |
| 模型名称 | `claude-sonnet-4-6` | 支持 Claude/GPT 等任何 Vision 模型 |
| AI 模式 | 仅弹窗检测 | 关闭 / 仅弹窗检测 / 完整 AI 驱动 |

### 8.2 API Key 存储

- 存储在 `secrets/ai_api_key`（与飞书 PAT 相同的本地文件加密方式）
- API 转发地址和模型名称存在 `settings.json`（非敏感信息）
- 管理员在每台电脑上配置一次即可，更新 App 不丢失

### 8.3 同事使用方式

1. 管理员注册 unifyllm.com，充值获取 API Key
2. 在每台同事电脑的 App 设置页填入 API 地址和 Key
3. 所有人共用同一个 Key 和额度
4. 月费用约 $50-80（50 条/天）

## 九、迁移策略

### Phase 1：AI 辅助（2-3 天）
- 保留现有代码流程
- 在关键节点加 AI 截图验证（弹窗检测、状态确认）
- AI 失败时 fallback 到现有逻辑

### Phase 2：AI 驱动（3-5 天）
- 封面设置、发布按钮等不稳定操作改为 AI 定位
- 弹窗处理完全交给 AI
- 验证码检测用 AI

### Phase 3：全面 AI（5-7 天）
- 整个发布流程用 AI 编排
- 只保留 CDP 执行层和基础导航
- 支持自动适应页面变化

## 十、风险和对策

| 风险 | 影响 | 对策 |
|------|------|------|
| API 调用延迟（2-5s/次） | 发布速度变慢 | 混合架构：简单操作不调 AI |
| API 费用 | 日均 $2-5 | 混合模式 + 截图压缩，只在需要时调 AI |
| AI 幻觉（返回错误坐标） | 点击错位 | 操作后截图验证，错误时重试（最多 3 次） |
| 转发服务不可用 | 无法使用 AI | 保留旧方案作为 fallback，AI 关闭时回退 |
| 截图隐私 | 页面内容发送到转发服务 | 用户知情同意，Key 自管，可随时关闭 AI |
| 转发服务换地址 | API 不通 | 设置页可自定义 API 地址，用户可随时切换 |
