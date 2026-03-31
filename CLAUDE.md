# 抖音发布助手 (DouyinUploader)

## 开发流程（重要）

每次修改代码后，Claude 必须自动执行以下命令，在 Xcode 中触发 ⌘R 构建并运行：

```bash
osascript -e 'tell application "Xcode" to activate' -e 'delay 0.5' -e 'tell application "System Events" to tell process "Xcode" to keystroke "." using command down' -e 'delay 1' -e 'tell application "System Events" to tell process "Xcode" to keystroke "r" using command down'
```

这条命令会：激活 Xcode → ⌘. 停止旧进程 → ⌘R 构建并运行。用户不需要做任何操作。

## 测试

```bash
cd /Users/menggang/www/douyin_upload/DouyinUploader
swift test
```

## 用 Xcode 打开（仅浏览代码/调试）

```bash
open -a Xcode /Users/menggang/www/douyin_upload/DouyinUploader/Package.swift
```

## 技术约束

- Swift 5.9+ / SwiftUI，macOS 13.0+ (Ventura)
- Universal Binary (Intel + M 系列)
- **零第三方依赖**，全部使用系统框架
- 不上架 App Store，不开启 Sandbox
- App 入口使用 NSApplication 手动启动（非 SwiftUI @main，因为 SPM executableTarget 不支持）
- 敏感数据存 `~/Library/Application Support/com.menggang.douyin-uploader/secrets/`（本地文件，不用系统 Keychain，避免弹密码框）

## 飞书表格列名（10 列必须 + 1 列可选 = 共 11 列）

抖音账号 | 抖音名称(可选) | 作品素材 | 作品标题 | 作品文案 | 话题标签 | 音乐名称 | 发布状态 | 发布时间 | 定时发布时间 | 失败原因

## 打包发布注意事项

### App 结构（必须严格遵守）

```
DouyinUploader.app/
├── Contents/
│   ├── Info.plist              # 需含 CFBundleIconFile
│   ├── MacOS/DouyinUploader    # Release 二进制
│   └── Resources/AppIcon.icns  # 图标
└── DouyinUploader_DouyinUploader.bundle/  # ⚠️ 必须在 .app 根目录！
    ├── JS/                                #   Bundle.module 从这里查找
    └── Resources/
```

> `DouyinUploader_DouyinUploader.bundle` **不能放在** `Contents/Resources/` 下，否则 `Bundle.module` 找不到会 `fatalError` 闪退。SPM 生成的 `resource_bundle_accessor.swift` 查找路径是 `Bundle.main.bundleURL`（即 `.app/` 根目录）。

### Chrome 必须保持可见窗口（headless: false）

`CDPPublishService` 中 `launchChrome(headless: false)` 不能改为 `true`，原因：
- 抖音会触发验证码验证（滑块、图片识别等）
- headless 模式下用户无法看到和操作验证码
- Chrome 窗口可见才能让用户手动处理验证

### 打包命令参考

```bash
# 1. 构建
cd DouyinUploader && swift build -c release

# 2. 组装 .app（注意 bundle 放根目录）
mkdir -p release/DouyinUploader.app/Contents/{MacOS,Resources}
cp .build/release/DouyinUploader release/DouyinUploader.app/Contents/MacOS/
cp .build/DouyinUploader.app/Contents/Info.plist release/DouyinUploader.app/Contents/
cp icon/AppIcon.icns release/DouyinUploader.app/Contents/Resources/
cp -R .build/release/DouyinUploader_DouyinUploader.bundle release/DouyinUploader.app/

# 3. 去隔离属性
xattr -cr release/DouyinUploader.app

# 4. 打包 DMG
hdiutil create -volname "抖音发布助手" -srcfolder /tmp/dmg_staging -ov -format UDZO output.dmg
```

### 已踩过的坑

| 问题 | 原因 | 解决 |
|------|------|------|
| 同事打开提示「已损坏，无法打开」 | macOS Gatekeeper 隔离属性 | 用户执行 `xattr -cr /Applications/DouyinUploader.app` |
| 打开后闪退 | Bundle 放在 `Contents/Resources/` 下，`Bundle.module` 找不到 | Bundle 必须放 `.app/` 根目录 |
| 点击「开始执行」无反应 | Chrome 未安装，代码静默 return | 已改为自动下载 Chrome |
| Chrome 窗口不显示 | `headless: true` | 必须 `headless: false`，否则验证码无法处理 |
| 端口 9222 冲突 | 硬编码端口 | 已改为动态查找可用端口 |
| force unwrap 闪退 | `.first!`、`URL()!` | 全部改为安全解包 |
| 检查登录状态误判为过期 | `validateCookies` 只检查 `data.user.unique_id` 路径，但抖音接口返回 `user` 在顶层 | 改为多路径查找 + user 非空即有效 |
| 设置封面点了「设置封面」标题无反应 | "设置封面"是模块标题，"选择封面"才是按钮 | 只匹配"选择封面"关键字 |
| 音乐下载时登录过期未检测 | MusicDownloader 导航到文章页后未检测 URL | 添加 `checkLoginExpired` |
| 页面内音乐选择失败 | 抖音页面"添加音乐"按钮交互复杂 | 已废弃，改用 MusicDownloader 下载 + AVFoundation 合并 |

## 调试日志

Cookie 登录状态检测会写调试日志到文件，方便排查问题：

```
~/Library/Application Support/com.menggang.douyin-uploader/debug-logs/cookie_check.log
```

查看日志：
```bash
cat ~/Library/Application\ Support/com.menggang.douyin-uploader/debug-logs/cookie_check.log
```

日志内容包括：HTTP 状态码、Cookie 数量、抖音接口返回的完整 JSON（前1000字符）、判定路径和结果。

## 相关文档

- `docs/PRD.md` — 产品需求文档 (v1.8)
- `docs/AI_REFACTOR_DESIGN.md` — AI 驱动重构设计文档（重要）
- `docs/TECH_RESEARCH.md` — 技术调研报告
- `docs/TEST_SCENARIOS.md` — 测试场景清单
- `docs/SPIKE_RESULTS.md` — Spike Test 验证结果
