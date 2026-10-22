## 2026-10-22 | 任务：统一修饰键的选区翻译与鼠标取词

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-22-unified-option-selection.md)

### 执行上下文

- **Agent Name:** `Codex`
- **Model:** `GPT-6`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

统一使用 Option：选词、划句或选择多段文字后翻译选区，没有选区时继续鼠标取词和按住译段落，
保留原文结构及自动复制功能，后台完成。后续要求选区与未选中的段落翻译使用相同的轻量浮动卡片，并根据截图修复列表挤成一段和浮窗宽度固定的问题。

### 变更

- 修饰键按下时异步探测活动应用的 AX 选区，释放时优先翻译精确选区；有选区时不进入段落模式。
- 无选区时保留轻按查词、按住译段落；组合键、点击、滚动、切换应用和新的修饰键取消待处理动作。
- 选区探测复用现有原生 AX 与 Text Marker 读取，上限为 350 ms，无固定等待，不模拟复制或写剪贴板。
- 选区与段落共用阅读卡片、样式和流式翻译链路；移除本任务早期引入的完整窗口入口，普通查询窗口快捷键保持不变。
- 选区卡片锚定手势所在位置，不抢占原应用；短译文自适应高度，长译文在有高度上限的卡片内滚动，保留全部内容。
- 选区不跳过母语文本、不复用悬停缓存；成功且未取消时按已有设置自动复制，失败或取消时不写剪贴板。
- 选区按原有硬换行分段，恢复句末标点后紧接项目符号的 AX 列表边界；最多三段并发翻译，每段隔离服务状态并保持统一语言方向，结果按原顺序重组。
- 本地保留段间分隔符、列表或标题前缀、缩进和尾部空白，完整成功后才自动复制。
- 选区浮窗根据原文测量及可用屏幕选择宽度，译文高度动态测量；阅读结果增加段落间距，长内容可滚动。
- 新增 `ReadingText` 生产组件及 Xcode 工程引用。
- 选区查询保留换行、缩进和列表标记；停止凭纯文本猜测 PDF 视觉换行，绕过输入清理规则。
- 先设置查询动作再传递输入文本，同一文本切换查询模式时重新计算实际请求文本。

### 设计意图

选区是用户明确指定的范围，优先于指针位置。复用现有事件协调器、选区读取和阅读卡片，避免添加
竞争监听器、复制模拟或另一个窗口。缺少可靠的选区坐标时使用鼠标位置锚定卡片。纯文本缺少布局证据，
保留其结构比自动合并换行可靠。将段落与列表标记留在应用本地，避免仅依赖模型保留结构；只恢复有明确句末标点和项目符号的拼接边界，不猜测普通句子的分段，不声称能恢复源文本未提供的富文本样式。

### 验证

- 本轮 Release 通用构建、四个 Swift 文件严格 lint、工程 plist 和差异检查通过；修复新增主线程隔离警告后完成最终构建。编译器自行恢复既有 CocoaLumberjack 缓存诊断，最终退出码为 0。
- 直接运行新增生产解析器检查已有真实取词记录：无换行列表恢复为四个块、三个边界，恢复后内容与项目符号可无损重组。未创建测试或 fixture，也未将此诊断描述为端到端验证。
- 上一阶段的五项现有超时测试在临时 SwiftPM 环境通过；本轮没有直接覆盖卡片路径的现有测试，未增加测试代码。
- Review 未发现阻塞问题，本轮检查文本结构、并发上限、结果顺序、服务隔离、取消与自动复制、卡片尺寸及工程引用，生产摘要一致。
- 已备份并安装，严格签名校验通过；指定签名要求、原图标和 Info.plist 保留，新进程权限仍允许。
- 未启动会显示窗口和注册全局快捷键的完整测试宿主；实际手势、卡片滚动、焦点和模型输出格式尚未现场验证。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/HoverTranslationManager.swift`
- `Easydict/Swift/Feature/ActionManager/ActionManager.swift`
- `Easydict/Swift/Feature/ActionManager/ReadingText.swift`
- `Easydict.xcodeproj/project.pbxproj`
- `Easydict/Swift/Feature/ActionManager/TranslationPreviewView.swift`
- `Easydict/Swift/Feature/ActionManager/TranslationPreviewPanel.swift`
- `Easydict/Swift/Utility/SystemUtility/SystemUtility+Selection.swift`
- `Easydict/Swift/Model/QueryModel.swift`
- `Easydict/objc/ViewController/Window/WindowManager/EZWindowManager.h`
- `Easydict/objc/ViewController/Window/WindowManager/EZWindowManager.m`
- `Easydict/objc/ViewController/Window/BaseQueryWindow/EZBaseQueryViewController.m`
- 本任务计划与历史记录。

### 后续事项

- 未提供 AX 选区或超时的应用会回退鼠标取词；纯文本不含字体、颜色和富文本强调。
- 源文本提供的换行、段落和列表标记由应用保留；原应用未提供的富文本样式、缺乏明确边界的拼接文本仍无法恢复。
- 硬换行会分开请求，多段选择需要多个翻译请求；实际跨应用操作与实时模型输出需现场验证。
