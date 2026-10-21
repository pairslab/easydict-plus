## 2026-10-21 | 任务：按住修饰键悬停翻译段落

**Links:** 个人分支 `personal/main`

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 27.2 / Xcode 27.0 (27A5252f)`

### 用户请求

阅读英文时希望不选中文字也能翻译整段：参考沉浸式翻译、DeepL、PopClip、系统"查询"等闭源软件的交互，
做一个优雅的"指哪翻哪"方式。

### 变更

- 新增悬停翻译：单独按住触发键（默认 ⌃）0.25 秒后，鼠标下的段落显示强调色描边，并随鼠标在段落间
  滑动；停留 0.35 秒或松开按键后，在段落正下方显示与原文左对齐的译文卡片。移开鼠标、滚动、点击、
  按键或切换应用时卡片淡出。原文已是第一语言时不显示卡片；译文按服务和原文缓存。
- `ParagraphLocator` 通过 Accessibility 读取鼠标下的段落：网页优先使用 WebKit/Chromium 的文本标记
  （段落范围、文本、边界），其次取最近的块级元素；原生文本视图按字符位置与换行拆段；其余元素取自身
  文字。要求鼠标落在段落范围内，拒绝过高（整页）的范围。
- 替换预览组件改名为 `TranslationPreview*`，增加阅读布局（宽度随段落、字号 15、完成后无状态标签）
  和文本对齐锚点，供替换翻译与悬停翻译共用。
- 高级设置新增"悬停翻译"触发方式（关闭 / ⌃ / ⌥ / ⇧），新增设置拆分到 `TextAssistSettingsSections`，
  避免 `AdvancedTab` 超出 SwiftLint 类型长度限制。
- 修复：抽取阅读翻译接口时改为从 `QueryModel.queryText` 取原文，而 `DetectManager` 只填写语言，导致
  发送空文本（悬停翻译显示模型的"未提供文本"回复，`⌥R` 把该回复写回输入框）。现在检测后写入
  `inputText`，向模型发送用户原文，并在原文为空时直接报错、不写回。该问题也使非流式服务（DeepL 等）
  的替换翻译一直收到空查询，一并修复。

### 设计意图

交互遵循主流软件的共同做法：明确意图才触发（单独按住修饰键，按下其他键即取消，避免与快捷键和打字
冲突）、就地显示、用完即走、原生质感。段落定位与翻译在后台队列和异步任务中进行，鼠标移动时只保留
最新位置，避免阻塞主线程。

### 验证

- `xcodebuild build`（Debug）：BUILD SUCCEEDED，新增与修改文件无编译或 SwiftLint 警告。
- `jq -e . Easydict/App/Localizable.xcstrings`、`plutil -lint project.pbxproj`、`git diff --check`：通过。
- 用户实测（修复前）：段落描边与卡片位置正确，日志显示段落被识别为英文，但译文为模型的空文本回复。
- 回归：TextEdit 中 `⌥R` 日志记录发送 18 个字符，并正确替换为英文译文。
- 未验证：修复后的悬停翻译端到端效果（Safari 自动化测试因用户正在使用前台应用而被安全中止），
  以及 Chrome、PDF 阅读器中的段落定位。

### 受影响文件

- `Easydict/Swift/Feature/HoverTranslation/HoverTranslationManager.swift`
- `Easydict/Swift/Feature/HoverTranslation/HoverTranslationTrigger.swift`
- `Easydict/Swift/Feature/HoverTranslation/ParagraphLocator.swift`
- `Easydict/Swift/Feature/HoverTranslation/ParagraphHighlightPanel.swift`
- `Easydict/Swift/Feature/ActionManager/ActionManager.swift`
- `Easydict/Swift/Feature/ActionManager/TranslationPreviewView.swift`
- `Easydict/Swift/Feature/ActionManager/TranslationPreviewPanel.swift`
- `Easydict/Swift/View/SettingView/Tabs/TabView/AdvancedTab.swift`
- `Easydict/Swift/View/SettingView/Tabs/TabView/TextAssistSettingsSections.swift`
- `Easydict/Swift/Feature/Configuration/Defaults.Keys+Extension.swift`
- `Easydict/App/AppDelegate.m`
- `Easydict/App/Localizable.xcstrings`
- `Easydict.xcodeproj/project.pbxproj`

### 后续事项

- 在 Chrome、Electron 应用和 PDF 阅读器中实测段落定位；必要时补充块级元素的识别规则。
