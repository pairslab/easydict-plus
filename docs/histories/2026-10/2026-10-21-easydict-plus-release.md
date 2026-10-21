## 2026-10-21 | 任务：Easydict Plus 首个安装包发布

**Links:** `pairslab/easydict-plus` Release `v2.25.0-plus.1`

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 27.2 / Xcode 27.0 (27A5252f)`

### 用户请求

打包一个可直接下载安装的 App 放到 GitHub Releases，并在 README 中补充下载安装说明。

### 变更

- Release 配置使用独立身份：Bundle ID `com.pairslab.EasydictPlus`，显示名 "Easydict Plus"，URL Scheme
  `easydictplus`，与官方 Easydict 共存且设置独立。Debug 配置保持不变。
- `AnalyticsService` 仅在官方 Bundle ID 下初始化 Firebase、Sentry 并记录统计，fork 不再向原作者的
  项目上报。
- Sparkle 更新源改为本仓库的 `appcast-plus.xml`（暂无条目），应用内检查更新不会安装官方版本。
- 首次启动的默认快捷键新增「翻译并替换」`⌥R` 与「润色并替换」`⇧⌥R`。
- README 新增"下载安装包"方式、首次打开放行步骤（隐私与安全性中"仍要打开"或移除隔离属性）、
  校验方式、升级与隐私说明。

### 设计意图

没有 Developer ID 证书，安装包采用 ad-hoc 签名的 Universal（arm64 + x86_64）Release 构建，签名设置通过
外部 xcconfig 在构建时覆盖，不改动工程中原作者的签名配置。上报改为按 Bundle ID 判断，合并上游后官方
构建行为不变。

### 验证

- `xcodebuild build -configuration Release -xcconfig <ad-hoc 签名覆盖>`：BUILD SUCCEEDED；
  `lipo -archs` 为 `x86_64 arm64`；Bundle ID、显示名、版本 2.25.0 (68)、最低系统 13.0、更新源均符合预期；
  `codesign --verify --deep --strict` 通过（ad-hoc + hardened runtime）。
- Debug 构建：BUILD SUCCEEDED。
- DMG（57.5 MB）`hdiutil verify` 通过；挂载后直接启动 App 正常运行，日志无 Firebase/Sentry 记录，
  系统日志中无上报相关域名。
- 未验证：在另一台带隔离属性的 Mac 上首次打开的放行流程（README 给出两种方式）。

### 受影响文件

- `Easydict.xcodeproj/project.pbxproj`
- `Easydict/App/Info.plist`、`Easydict/App/Info-debug.plist`
- `Easydict/Swift/Utility/Logging/AnalyticsService.swift`
- `Easydict/Swift/Feature/Shortcut/Model/ShortcutManager+Default.swift`
- `appcast-plus.xml`
- `README.md`

### 后续事项

- ad-hoc 签名的安装包每次升级后需重新授予辅助功能权限；如需免除，需使用 Developer ID 签名并公证。
