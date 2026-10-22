## 2026-10-22 | 任务：统一修饰键的选区翻译与鼠标取词

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-22-unified-option-selection.md)

### 执行上下文

- **Agent Name:** `Codex`
- **Model:** `GPT-6`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

统一使用 Option：选词、划句或选择多段文字后翻译选区，没有选区时继续鼠标取词和按住译段落，
保留原文结构及自动复制功能，后台完成。

### 变更

- 修饰键按下时异步探测活动应用的 AX 选区，释放时优先翻译精确选区；有选区时不进入段落模式。
- 无选区时保留轻按查词、按住译段落；组合键、点击、滚动、切换应用和新的修饰键取消待处理动作。
- 选区探测复用现有原生 AX 与 Text Marker 读取，上限为 350 ms，无固定等待，不模拟复制或写剪贴板。
- 新增接收已获取选区的窗口入口，复用完整翻译窗口和自动复制设置，避免重新取词或截断多段选区。
- 选区查询保留换行、缩进和列表标记；停止凭纯文本猜测 PDF 视觉换行，绕过输入清理规则。
- 先设置查询动作再传递输入文本，同一文本切换查询模式时重新计算实际请求文本。

### 设计意图

选区是用户明确指定的范围，优先于指针位置。复用现有事件协调器、选区读取和结果窗口，避免添加
竞争监听器或复制模拟。纯文本缺少布局证据，保留其结构比自动合并换行可靠；沿用已有格式保持提示词，
而不声称能恢复源文本未提供的富文本样式。

### 验证

- Release 构建、修改 Swift 文件严格 lint、差异检查通过。
- 五项现有超时测试在临时 SwiftPM 环境通过，测试和相关生产实现原样复用；未增加测试代码。
- Review 未发现阻塞问题，检查了手势取消、选区优先、请求模型复制与自动复制路径，生产摘要一致。
- 已备份并安装，严格签名校验通过；指定签名要求、原图标和 Info.plist 保留，新进程权限仍允许。
- 未启动会显示窗口和注册全局快捷键的完整测试宿主；实际手势和模型输出格式尚未现场验证。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/HoverTranslationManager.swift`
- `Easydict/Swift/Utility/SystemUtility/SystemUtility+Selection.swift`
- `Easydict/Swift/Model/QueryModel.swift`
- `Easydict/objc/ViewController/Window/WindowManager/EZWindowManager.h`
- `Easydict/objc/ViewController/Window/WindowManager/EZWindowManager.m`
- `Easydict/objc/ViewController/Window/BaseQueryWindow/EZBaseQueryViewController.m`
- 本任务计划与历史记录。

### 后续事项

- 未提供 AX 选区或超时的应用会回退鼠标取词；纯文本不含字体、颜色和富文本强调。
- 译文结构仍取决于翻译服务遵循提示词，实际跨应用操作与模型输出需现场验证。
