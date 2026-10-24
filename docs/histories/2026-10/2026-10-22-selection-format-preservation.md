## 2026-10-22 | 任务：划词翻译保留原文格式

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-22-selection-format-preservation.md)

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

保留手动划词翻译，并让译文尽量保留原文的段落、换行、列表与标题结构；PDF 视觉折行不应把句子切碎，
也不能一概合并换行破坏有意的格式。

### 变更

- AI 翻译系统提示词要求保留段落、换行、列表符号与编号和标题，不合并或拆分段落。
- 新增 `joiningWrappedLines`：仅当上一行未以句末或分句标点结束、下一行以小写字母开头且不是字母列表项时合并，
  并删除拆分单词的行尾连字符；空行、列表、标题、缩进行与中文行保持换行。
- 划词类查询（快捷键、自动划词、外部调用）在进入查询窗口前应用该合并；手动输入不受影响。

### 设计意图

只合并有明确续句证据的折行，宁可保留少数可合并的换行，也不破坏用户有意的结构。格式要求放在系统提示词中，
不改动服务请求与路由。选区以纯文本提供，粗体、斜体等强调无法保留。

### 验证

- Release arm64 构建、SwiftLint strict、`git diff --check` 通过；折行合并独立测试 14/14 通过。
- 已安装，签名指定要求、原图标、`Info.plist` 与配置保持。

### 受影响文件

- `Easydict/Swift/Service/OpenAI/StreamService+Prompt.swift`
- `Easydict/Swift/Utility/Extensions/String/String+HandleInputText.swift`
- `Easydict/objc/ViewController/Window/WindowManager/EZWindowManager.m`
- 本任务计划和历史记录。

### 后续事项

- 以大写字母开头的真实续行（如专有名词）保持换行；模型是否完全遵循格式要求取决于模型。
- 轻按 Option 翻译选区尚未实现，待用户确认。

### 后续调整

- 统一选区入口时改为原样保留选区的换行，不再按文本猜测合并折行；`joiningWrappedLines` 随之失去调用者，已删除。
  格式保留由翻译提示词与选区原文结构承担。
