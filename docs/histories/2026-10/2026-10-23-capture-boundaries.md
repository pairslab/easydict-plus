## 2026-10-23 | 任务：收紧取词与段落捕获边界

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-23-capture-boundaries.md)

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

Option 取词有时捕获过多无关、杂乱的文字；要求通用修复浏览器、Electron、原生应用和 PDF 中的捕获边界，
保留选区优先与精确性、轻按单词与按住段落的行为。

### 变更

- `TextRunReader` 只跨出链接收集文字片段，不再在单片段父块时向上爬升到整篇内容；收集时跳过按钮、菜单、输入框等控件文字。
- 段落捕获记录来源、字符数与高度（不含文字），便于诊断。
- 曾尝试按指针位置或“是否已翻译”判断残留选区，Review 认为会丢弃有效选区，已撤回；选区语义与 `77f1268` 一致。

### 设计意图

爬升到整篇内容并混入控件文字是按住取段落过度捕获的通用来源，修复只改变从哪个块收集片段，不截断合法文本、不增加延迟、
不针对特定网站。选区新旧无法可靠判断，因此保留“任何明确选区优先”的既有行为。

### 验证

- Release arm64 构建、SwiftLint strict、`git diff --check` 通过；版面测试 19/19 通过。
- 已安装，签名、原图标、`Info.plist` 与偏好设置保持。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/WordLocator.swift`
- `Easydict/Swift/Feature/ReadingAssist/ParagraphLocator.swift`
- 本任务计划和历史记录。

### 后续事项

- 残留的明确选区（例如为复制而选中）仍优先于指针；需取消选区后再轻按单词。
- 实际手势效果待用户确认。
