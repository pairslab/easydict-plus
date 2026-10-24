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

- 新增 `SelectionGeometry`：用网页文本标记范围或原生选中范围的屏幕边界，判断指针是否在选区上；指针位于其他应用时不采用；
  边界不可得时以焦点文本元素框架判断。`readingSelection(at:)` 只在指针指向选区时返回选区文字，文字本身不变。
- `TextRunReader` 只跨出链接收集文字片段，不再在单片段父块时向上爬升；收集时跳过按钮、菜单、输入框等控件文字。
- 段落捕获记录来源、字符数与高度（不含文字），便于诊断。

### 设计意图

残留选区与爬升到整篇内容是过度捕获的两个通用来源。修复只改变何时采用选区和从哪个块收集片段，不截断合法文本，
不增加延迟，也不针对特定网站。

### 验证

- Release arm64 构建、SwiftLint strict、`git diff --check` 通过；版面测试 19/19 通过。
- 已安装，签名、原图标、`Info.plist` 与偏好设置保持。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/AXElementReader.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLocator.swift`
- `Easydict/Swift/Feature/ReadingAssist/ParagraphLocator.swift`
- `Easydict/Swift/Feature/ReadingAssist/HoverTranslationManager.swift`
- `Easydict/Swift/Utility/SystemUtility/SystemUtility+Selection.swift`
- 本任务计划和历史记录。

### 后续事项

- Chromium 基础模式下选区边界为空时，同一文档中的残留选区仍会被采用，直到页面建立完整文字几何。
- 实际手势效果待用户确认。
