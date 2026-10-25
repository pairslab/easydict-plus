## 2026-10-25 | 任务：翻译卡片渲染 LaTeX 公式

**Links:** 基线 `7662b36`

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

在翻译结果中加入 LaTeX 渲染。

### 变更

- 引入 SwiftMath 1.7.3（MIT，纯 Swift，自带 Latin Modern 等数学字体），新增 `MathText`：
  - `$…$`、`\(…\)` 行内渲染，`$$…$$`、`\[…\]` 单独成行居中，过宽时等比缩小。
  - 单个 `$` 采用 Pandoc 规则（起始 `$` 后不接空白、结束 `$` 前不为空白且后不接数字、不跨行），`$5 and $10`
    这类金额保持原样；`\$` 显示为 `$`。
  - 公式渲染为模板图像，跟随正文颜色（深色模式可用），按公式基线对齐；渲染结果（含失败）缓存，流式更新不重复解析。
  - 无法解析的公式或尚未闭合的分隔符按原文显示。
- 阅读卡片（悬停段落、选区翻译）使用 `MathText`；写回预览仍显示原文，因为写入文档的就是原文。
- 阅读翻译请求在系统提示词后追加“数学内容用 LaTeX 书写”的要求（`StreamService.writesMathAsLaTeX`，仅阅读翻译开启），
  主窗口翻译与替换写回不受影响；用户自定义提示词时不追加。

### 设计意图

PDF 中提取的公式多为散乱的 Unicode 符号，仅渲染模型原样返回的 LaTeX 效果有限，所以只在会渲染的卡片里请求 LaTeX
输出，避免主窗口和写回文本出现 `$…$` 源码。

### 验证

- Debug、Release arm64 构建，SwiftLint strict 通过；Release 包含 `SwiftMath_SwiftMath.bundle`（数学字体）。
- 解析规则用独立脚本检查：金额、转义美元、行内/块级公式、空行均符合预期。
- 未验证：实际卡片中的公式视觉效果与模型是否稳定输出 LaTeX。

### 受影响文件

- `Easydict/Swift/Feature/ActionManager/MathText.swift`（新增）
- `Easydict/Swift/Feature/ActionManager/TranslationPreviewView.swift`
- `Easydict/Swift/Feature/ActionManager/ActionManager.swift`
- `Easydict/Swift/Service/OpenAI/StreamService.swift`
- `Easydict/Swift/Service/OpenAI/StreamService+Prompt.swift`
- `Easydict.xcodeproj/project.pbxproj`、`Easydict.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- 本任务历史记录。

### 后续事项

- SwiftMath 不支持的命令会使整条公式回退为原文显示；如常见公式出现这种情况，再考虑预处理。
