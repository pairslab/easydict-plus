## 2026-10-24 | 任务：PDF 选区长按仍走段落翻译

**Links:** 基线 `f4a78a2`

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

在 PDF 中选中文字后长按修饰键，仍进入段落翻译。

### 变更

- 日志（20:14，Edge PDF）显示每次按住都进入段落模式，从未读到选区：Chromium PDF 查看器与网页把文档选区记录在
  `AXSelectedTextMarkerRange`，焦点元素的选中文本属性为空。
- 常规读取为空时，读取指针下方或焦点所在网页文档的文本标记选区（只读，不复制、不访问剪贴板），时限 0.25 s。
- 有选区时长按松开也翻译选区（同一选区卡片显示时再按仍为关闭）；只有无选区时，未进入段落模式的长按才被忽略。

### 设计意图

选区读不到时手势只能按无选区处理；补上文档级选区读取后，选区优先在 PDF 中同样成立。长按翻译选区符合“选中后
按住”的预期，重复请求由“再按关闭”避免。

### 验证

- Release arm64 构建、SwiftLint strict 通过。
- 未验证：Edge PDF 中实际读取选区的效果（取决于 Chromium 是否同步 PDF 选区到辅助功能树）。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/AXElementReader.swift`
- `Easydict/Swift/Feature/ReadingAssist/HoverTranslationManager.swift`
- `Easydict/Swift/Utility/SystemUtility/SystemUtility+Selection.swift`
- 本任务历史记录。

### 后续事项

- 若 Edge PDF 仍读不到选区，只能通过复制命令读取，会触及剪贴板，需要用户决定是否接受。
