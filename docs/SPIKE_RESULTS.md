# Spike Test 验证结果

> 状态：已完成 | 创建日期：2026-03-26 | 更新日期：2026-03-30

## 验证清单

| # | 测试项 | 状态 | 结果 | 备注 |
|---|--------|------|------|------|
| S1 | Chrome for Testing 下载+启动 | ✅ 已通过 | Chrome 131.0.6778.204 自动下载并启动成功 | arm64/x64 架构自动识别 |
| S2 | CDP 文件上传 | ✅ 已通过 | `DOM.setFileInputFiles` 成功触发抖音上传 | 无需用户手势，比 WKWebView 更可靠 |
| S3 | CDP Cookie 注入 | ✅ 已通过 | `Network.setCookies` 注入后页面正常加载 | 按账号独立 Chrome 用户数据目录 |
| S4 | WKWebView 扫码登录 | ✅ 已通过 | 弹窗中扫码成功，Cookie 和用户信息提取正确 | WKWebView 仅用于登录 |
| S5 | 抖音创作者中心 CDP 操作 | ✅ 已通过 | CDP 可查询 DOM、执行 JS、键盘输入 | 防检测参数 `--disable-blink-features=AutomationControlled` |
| S6 | 飞书 API 读取 | ✅ 已通过 | PAT 认证读取记录成功 | 自动分页（page_size=500） |
| S7 | 飞书 API 写入 | ✅ 已通过 | PATCH 更新记录成功 | 发布状态、时间、失败原因 |
| S8 | 飞书附件下载 | ✅ 已通过 | 附件下载成功，文件大小匹配 | 含重试机制（最多3次） |
| S9 | 音乐下载+合并 | ✅ 已通过 | CDP 网络拦截下载音乐，AVFoundation 合并视频 | 背景音乐 30% 音量 |
| S10 | 账号隔离 | ✅ 已通过 | 独立 Chrome 用户数据目录，Cookie 不互相影响 | `chrome-profiles/{accountId}/` |

## 技术方案最终选择

### 浏览器方案

**最终采用**：Chrome for Testing + Chrome DevTools Protocol (CDP)

**选择原因**：
- `DOM.setFileInputFiles` 可直接设置文件路径，完全绕过用户手势限制
- 每个账号独立 Chrome 用户数据目录，天然实现 Cookie 隔离
- CDP WebSocket 通信稳定，支持网络拦截（用于音乐下载）
- 比 WKWebView 的 `runOpenPanel` 拦截方案更可靠

**WKWebView 保留用途**：仅用于扫码登录弹窗（`QRCodeLoginView`）

### 音乐方案

**最终采用**：CDP 网络拦截下载 + AVFoundation 合并

**选择原因**：
- 避免抖音页面内音乐选择器的复杂交互（React 受控组件、Hash 可变 class 名）
- 通过文章发布页下载音乐文件，用 AVFoundation 合并到视频中再上传
- 更可靠，不受抖音页面 UI 变化影响

### 凭证存储

**最终采用**：本地文件 base64 编码（`secrets/` 目录）

**选择原因**：
- 系统 Keychain 每次访问会弹出密码输入框，影响自动化体验
- 本地文件存储简单可靠，base64 编码提供基本混淆

## 实际抓取的 CSS 选择器

选择器硬编码在 `CDPPublishService.swift` 中，采用文字内容匹配优先策略：

```json
{
  "publish": {
    "description_editor": ".zone-container[contenteditable='true']",
    "schedule_radio": "遍历 DOM 查找 textContent === '定时发布'",
    "schedule_input": "input[placeholder*='日期'], input[format*='yyyy']",
    "publish_button": "遍历按钮查找 textContent 含 '发布'",
    "title_input": "input[placeholder] (图文标题)"
  },
  "upload": {
    "file_input": "通过 CDP DOM.setFileInputFiles 直接设置"
  },
  "music": {
    "entry_button": "遍历 DOM 查找 textContent === '选择音乐'",
    "search_input": "input[placeholder='搜索音乐']",
    "audio_url_pattern": "douyinstatic.com/obj/tos-cn-* 或 bytecdn.cn"
  }
}
```
