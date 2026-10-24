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

- 新增 `SelectionGeometry`：用网页文本标记范围或原生选中范围的屏幕边界，判断指针是否在选区上；边界不可得时以焦点
  文本元素框架判断。选区仍优先且原样翻译；只有与上一次已翻译选区相同、且指针明确不在其上时才改读指针。
- `TextRunReader` 只跨出链接收集文字片段，不再在单片段父块时向上爬升；收集时跳过按钮、菜单、输入框等控件文字。
- 段落捕获记录来源、字符数与高度（不含文字），便于诊断。

### 设计意图

残留选区与爬升到整篇内容是过度捕获的两个通用来源。指针位置不能证明新选区过时，因此只把已翻译过、仍高亮的选区
视为残留。修复不截断合法文本，新选区不增加等待，也不针对特定网站。

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

- 从未通过手势翻译过的残留选区（例如为复制而选中）仍会优先；刻意重新选中相同文字并在别处轻按时读取指针。
- Chromium 基础模式下选区边界为空时保留选区，直到页面建立完整文字几何。
- 实际手势效果待用户确认。
