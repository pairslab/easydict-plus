## 2026-10-21 | 任务：发布 Easydict Plus 并编写中文使用指南

**Links:** `pairslab/easydict-plus`（fork 自 `tisfeng/Easydict`）

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 27.2 / Xcode 27.0 (27A5252f)`

### 用户请求

把个人分支发布到 pairslab 组织的新仓库，并写一份通俗易懂、图文并茂的中文说明，覆盖安装、只配置
DeepSeek 的设置步骤和各功能用法。

### 变更

- 根目录 `README.md` 改为 Easydict Plus 中文使用指南；原英文说明移至 `README_UPSTREAM.md`，并更新
  `README_UPSTREAM.md`、`README_ZH.md` 中的语言切换链接。
- 新增 `docs/assets/easydict-plus/` 配图：三张由真实卡片组件离线渲染的功能示意图，一张查询窗口截图，
  四张设置窗口截图（只截取 Easydict 窗口，API Key 以掩码显示）。
- `Info.plist` 与 `Info-debug.plist` 默认关闭 Sparkle 自动检查更新，避免增强版被官方版本覆盖。

### 设计意图

面向非开发者的读者按"安装 → 首次设置 → 使用"组织，所有设置只依赖 DeepSeek；费用说明区分免费的
查词与润色和计费的 DeepSeek 调用。保留原项目说明与 GPL-3.0 协议声明。

### 验证

- `xcodebuild build`（Debug）、`plutil -lint` 两个 Info.plist、`git diff --check`：见提交前检查。
- 检查工作区与本次分支全部提交中不含 DeepSeek API Key；设置截图人工确认 Key 为掩码。

### 受影响文件

- `README.md`、`README_UPSTREAM.md`、`README_ZH.md`
- `docs/assets/easydict-plus/*.png`
- `Easydict/App/Info.plist`、`Easydict/App/Info-debug.plist`

### 后续事项

- 如需让不会编译的用户直接使用，可在 GitHub Releases 提供打包好的 App（需处理签名与公证）。
