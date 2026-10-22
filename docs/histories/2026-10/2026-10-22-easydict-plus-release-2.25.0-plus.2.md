## 2026-10-22 | 任务：合并 PR #1 并发布 Easydict Plus 2.25.0-plus.2

**Links:** [PR #1](https://github.com/pairslab/easydict-plus/pull/1) · `pairslab/easydict-plus` Release `v2.25.0-plus.2` ·
[上一版发布记录](2026-10-21-easydict-plus-release.md)

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 27.2 / Xcode 27.0 (27A5252f)`

### 用户请求

按同事的方案合并 PR #1（轻按 Option 查词取代双击查词、加快悬停识别等），然后重新发布一个安装包版本。

### 变更

- 以 merge commit 合并 PR #1（`d4e7b663`），代码改动见
  [轻按修饰键查词](2026-10-21-option-tap-word-lookup.md) 与
  [加快悬停翻译识别](2026-10-21-hover-translation-responsiveness.md)。
- README 配图 `word-lookup.png` 改为指针停在单词上、轻按 `⌥ Option` 的场景，不再显示选中高亮；
  `settings-advanced.png` 重新截取，开关文案为"轻按 Option 查词"。
- README 升级问答补充：ad-hoc 签名的新版需在辅助功能列表中删除旧条目后重新添加。
- 发布 `v2.25.0-plus.2`：版本 2.25.0，构建号由 68 提升为 69，以区分 plus.1。

### 设计意图

构建号通过外部 xcconfig 覆盖，签名与打包方式沿用 plus.1，不改动工程中原作者的版本和签名配置。
配图沿用离线渲染场景与设置页辅助功能截图流程，与上一版图片取景一致。

### 验证

- 合并后的 Debug 构建：BUILD SUCCEEDED，无阅读辅助相关新增警告；本机调试版重启后悬停翻译正常启用。
- `xcodebuild build -configuration Release -xcconfig <ad-hoc 签名覆盖 + CURRENT_PROJECT_VERSION = 69>`：
  BUILD SUCCEEDED；`lipo -archs` 为 `x86_64 arm64`；Bundle ID `com.pairslab.EasydictPlus`、显示名、
  版本 2.25.0 (69)、最低系统 13.0、URL Scheme、更新源均符合预期；简体中文资源包含"轻按 Option 查词"；
  `codesign --verify --deep --strict` 通过（ad-hoc + hardened runtime）。
- DMG（57.6 MB）`hdiutil verify` 通过；挂载后 DMG 内 App 签名校验通过，直接启动运行合并后的代码，
  应用日志与系统日志均无 Firebase/Sentry 记录。
- 未验证：从 plus.1 覆盖升级后重新授权辅助功能的流程（README 与发布说明给出步骤）；轻按查词的
  跨应用实测以 PR #1 记录为准。

### 受影响文件

- `README.md`
- `docs/assets/easydict-plus/word-lookup.png`
- `docs/assets/easydict-plus/settings-advanced.png`

### 后续事项

- ad-hoc 签名的安装包每次升级后仍需重新授予辅助功能权限；如需免除，需使用 Developer ID 签名并公证。
