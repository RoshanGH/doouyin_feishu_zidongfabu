# 抖音发布助手 (DouyinUploader)

一款 macOS 原生桌面应用，通过飞书多维表格驱动，自动化批量发布内容到抖音创作者中心。

## 功能特性

- **飞书多维表格驱动** — 在飞书表格中管理素材、文案、话题、定时发布时间，App 自动读取并执行
- **多账号管理** — 支持多个抖音账号扫码登录，Cookie 持久化，过期自动检测
- **视频 & 图文发布** — 自动识别素材类型，走对应的发布流程
- **音乐融合** — 自动搜索并下载抖音音乐，合并到视频中再上传（背景音乐 30%，原声 100%）
- **话题标签** — 支持逗号分隔、换行分隔、`#` 前缀等多种格式，逐个输入到抖音话题选择器
- **定时发布** — 支持设置定时发布时间，精确到分钟
- **实时状态回写** — 发布结果（成功/失败/原因/时间）实时回写到飞书表格
- **执行日志** — 完整的执行日志记录，支持历史查看和导出
- **防风控** — 随机任务间隔、模拟人工操作节奏、串行执行

## 技术栈

| 项目 | 技术 |
|------|------|
| 语言 | Swift 5.9+ |
| UI | SwiftUI |
| 最低系统 | macOS 13.0 (Ventura) |
| 架构 | Universal Binary (Intel + Apple Silicon) |
| 浏览器自动化 | Chrome for Testing + CDP 协议 |
| 音乐合并 | AVFoundation |
| 第三方依赖 | **零依赖**，全部使用系统框架 |

## 项目结构

```
douyin_upload/
├── DouyinUploader/              # 主工程（SPM Package）
│   ├── Package.swift
│   ├── Sources/
│   │   ├── App/                 # 应用入口
│   │   ├── Models/              # 数据模型
│   │   ├── Views/               # SwiftUI 视图
│   │   ├── ViewModels/          # 视图模型
│   │   ├── Services/            # 业务服务
│   │   │   ├── Chrome/          # Chrome CDP 自动化
│   │   │   ├── Douyin/          # 抖音登录 & Cookie
│   │   │   └── Feishu/          # 飞书 API
│   │   └── JS/                  # 注入脚本
│   └── Tests/                   # 单元测试
├── DouyinUploaderApp/           # Xcode 项目配置
├── docs/                        # 项目文档
│   ├── PRD.md                   # 产品需求文档
│   ├── TECH_RESEARCH.md         # 技术调研报告
│   ├── TEST_SCENARIOS.md        # 测试场景清单
│   └── SPIKE_RESULTS.md         # 技术验证结果
└── CLAUDE.md                    # AI 开发指令
```

## 飞书表格格式

App 读取飞书多维表格数据，需按以下固定列名建表（11 列）：

| 列名 | 类型 | 必填 | 说明 |
|------|------|------|------|
| 抖音账号 | 文本 | 是 | 抖音号 |
| 抖音名称 | 文本 | 否 | 昵称，便于识别 |
| 作品素材 | 附件 | 是 | 图片或视频文件 |
| 作品标题 | 文本 | 否 | 仅图文使用 |
| 作品文案 | 文本 | 是 | 发布描述 |
| 话题标签 | 文本 | 否 | 逗号或换行分隔，可带 `#` |
| 音乐名称 | 文本 | 否 | 抖音音乐名称 |
| 发布状态 | 单选 | 是 | 允许发布 / 发布中 / 已发布 / 发布失败 |
| 发布时间 | 日期 | 否 | App 自动回写 |
| 定时发布时间 | 日期 | 否 | 如 `2026-03-26 18:00` |
| 失败原因 | 文本 | 否 | App 自动回写 |

## 快速开始

### 1. 构建运行

```bash
# 用 Xcode 打开
open -a Xcode DouyinUploader/Package.swift

# 或命令行测试
cd DouyinUploader && swift test
```

### 2. 配置飞书

1. 在飞书中创建多维表格，按上述格式建好列
2. 获取 Personal Access Token (PAT) 或创建自建应用
3. 在 App 中添加飞书配置，粘贴表格 URL，填入认证信息

### 3. 登录抖音

1. 点击「添加账号」，弹出扫码窗口
2. 用抖音 App 扫码并确认
3. App 自动提取 Cookie 和账号信息

### 4. 开始发布

1. 选择飞书配置 → 点击「读取任务」
2. 确认任务列表 → 点击「开始执行」
3. App 自动串行执行所有任务，实时显示进度

## 数据存储

所有数据存储在本地，不上传任何服务器：

```
~/Library/Application Support/com.menggang.douyin-uploader/
├── configs.json          # 飞书配置
├── accounts.json         # 账号列表
├── settings.json         # App 设置
├── secrets/              # 凭证（base64 编码）
├── logs/                 # 执行日志
├── chrome/               # Chrome for Testing（自动下载）
└── chrome-profiles/      # Chrome 用户数据（按账号隔离）
```

## 免责声明

- 自动化发布可能违反抖音平台的服务条款
- 大批量操作有触发风控或账号封禁的风险
- 本工具仅用于合法的内容运营场景，使用者需自行承担操作风险

## License

MIT
