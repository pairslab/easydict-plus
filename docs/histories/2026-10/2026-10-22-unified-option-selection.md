## 2026-10-22 | 任务：统一修饰键的选区翻译与鼠标取词

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-22-unified-option-selection.md)

### 执行上下文

- **Agent Name:** `Codex`
- **Model:** `GPT-6`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

统一使用 Option：选词、划句或选择多段文字后翻译选区，没有选区时继续鼠标取词和按住译段落，
保留原文结构及自动复制功能，后台完成。后续要求选区与未选中的段落翻译使用相同的轻量浮动卡片。

### 变更

- 修饰键按下时异步探测活动应用的 AX 选区，释放时优先翻译精确选区；有选区时不进入段落模式。
- 无选区时保留轻按查词、按住译段落；组合键、点击、滚动、切换应用和新的修饰键取消待处理动作。
- 选区探测复用现有原生 AX 与 Text Marker 读取，上限为 350 ms，无固定等待，不模拟复制或写剪贴板。
- 选区与段落共用阅读卡片、样式和流式翻译链路；移除本任务早期引入的完整窗口入口，普通查询窗口快捷键保持不变。
- 选区卡片锚定手势所在位置，不抢占原应用；短译文自适应高度，长译文在有高度上限的卡片内滚动，保留全部内容。
- 选区不跳过母语文本、不复用悬停缓存；成功且未取消时按已有设置自动复制，失败或取消时不写剪贴板。
- 选区查询保留换行、缩进和列表标记；停止凭纯文本猜测 PDF 视觉换行，绕过输入清理规则。
- 先设置查询动作再传递输入文本，同一文本切换查询模式时重新计算实际请求文本。

### 设计意图

选区是用户明确指定的范围，优先于指针位置。复用现有事件协调器、选区读取和阅读卡片，避免添加
竞争监听器、复制模拟或另一个窗口。缺少可靠的选区坐标时使用鼠标位置锚定卡片。纯文本缺少布局证据，
保留其结构比自动合并换行可靠；沿用已有格式保持提示词，
而不声称能恢复源文本未提供的富文本样式。

### 验证

- 本轮 Release 通用构建、四个修改 Swift 文件严格 lint、差异检查通过；编译器自行恢复 CocoaLumberjack 缓存诊断，最终退出码为 0。
- 上一阶段的五项现有超时测试在临时 SwiftPM 环境通过；本轮没有直接覆盖卡片路径的现有测试，未增加测试代码。
- Review 未发现阻塞问题，本轮检查选区路由、母语翻译、格式、取消、自动复制、卡片尺寸与滚动输入，生产摘要一致。
- 已备份并安装，严格签名校验通过；指定签名要求、原图标和 Info.plist 保留，新进程权限仍允许。
- 未启动会显示窗口和注册全局快捷键的完整测试宿主；实际手势、卡片滚动、焦点和模型输出格式尚未现场验证。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/HoverTranslationManager.swift`
- `Easydict/Swift/Feature/ActionManager/ActionManager.swift`
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
- 译文结构仍取决于翻译服务遵循提示词，实际跨应用操作与模型输出需现场验证。
