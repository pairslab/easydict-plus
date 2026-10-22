## 2026-10-21 | 任务：轻按修饰键查词

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-21-option-tap-word-lookup.md) · [PR #1](https://github.com/pairslab/easydict-plus/pull/1)

### 执行上下文

- **Agent Name:** `Codex`
- **Model:** `GPT-6`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

将双击单词显示词典卡片改为轻按一次 Option，保留已有段落翻译与翻译配置；修复误触段落、取词无反应并改善响应。

### 变更

- 同一事件入口协调短按查词与长按段落翻译。共用按键时，松开优先查词；持续按住约 500 ms 且物理按键仍按下才开始段落识别，轻按期间不高亮整段。
- 增加静态文本范围边界定位，适配 Electron 内容；通过范围矩形缩小候选，最多查询 64 次，避免逐词查询整段。
- 保留 web 文本标记与原生字符范围回退，web 范围扩展到单词两端，不依赖旧选区，不修改选区或剪贴板。
- 组合键、点击、滚动和应用切换取消短按或未完成查询；日志只记录手势、角色和查询次数，不记录读取内容。
- 显式应用初始设置，避免未写入的默认偏好阻止监听注册；移除双击专用词典入口，更新六种语言的设置文案和中文指南。

### 设计意图

短按和长按共用监听入口，避免段落流程抢占单词查询；其他段落触发键仍立即识别。
查词开关与段落触发设置独立，保留只读文本和既有翻译配置边界。
Chromium 的范围边界实现用于选择 Electron 取词路径，WebKit 实现用于核对文本标记范围；均不代表所有应用兼容性保证。

### 验证

- 初版及手势修复版 Release 通用构建通过；最终取词兼容修复版 Release arm64 构建通过。
- 初版六个、最终修复三个变更 Swift 文件通过 SwiftLint strict；String Catalog JSON 与差异格式检查通过。
- 已备份旧应用和配置并安装最终构建；严格签名校验、原配置保留、辅助功能刷新和启动检查通过。
- 最终源码与构建、审查快照一致；审查覆盖短按优先、范围矩形剪枝、完整单词边界及取消分支，未发现未解决的确定缺陷。
- 用户在 AgentsDock 中实测后确认可用；日志确认轻按展示单词卡片并取得语境，持续按住进入段落模式，静态文本取词示例使用 4–7 次边界查询。
- 未新增或扩写测试，现有测试不覆盖阅读辅助状态机；未进行跨应用完整回归或网络翻译耗时测量。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/HoverTranslationManager.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLookupManager.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLocator.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLookupCardView.swift`
- `Easydict/Swift/Feature/Configuration/Defaults.Keys+Extension.swift`
- `Easydict/Swift/Utility/EventMonitor/Core/EventMonitor.swift`
- `Easydict/App/Localizable.xcstrings`
- `README.md`
- 本任务计划和历史记录。

### 后续事项

无阻断项；其他应用的兼容性仍以各自的实际辅助功能支持为准。

参考：[WebKit 单词范围处理](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/accessibility/mac/WebAccessibilityObjectWrapperMac.mm)、[Chromium 辅助功能范围实现](https://github.com/chromium/chromium/blob/main/ui/accessibility/platform/browser_accessibility_cocoa.mm)。
