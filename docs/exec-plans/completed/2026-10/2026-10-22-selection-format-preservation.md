# 划词翻译保留原文格式

- 状态：completed
- 创建日期：2026-10-22
- 负责人：Claude Code
- 关联 Issue/PR：none

## 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

## 背景

用户希望翻译保留原文的段落、换行、列表与标题结构。现状：AI 翻译的系统提示词没有要求保留格式，
模型可能把多段文字合并；划词文本的换行只有“全部保留”或“全部替换为空格”两种处理，PDF 中按视觉行
断开的句子会被切成碎片。

## 目标与范围

- 目标结果：
  - 翻译系统提示词要求保留段落、换行、列表符号与编号、标题。
  - 划词查询（快捷键、自动划词图标、外部调用）只合并明显的 PDF 视觉折行：上一行未以句末或分句
    标点结束，且下一行以小写拉丁字母开头；行尾连字符在此情况下删除。空行、列表项、缩进行与标题保持不变。
- 允许修改路径：`Easydict/Swift/Service/OpenAI/StreamService+Prompt.swift`、
  `Easydict/Swift/Utility/Extensions/String/String+HandleInputText.swift`、
  `Easydict/objc/ViewController/Window/WindowManager/EZWindowManager.m` 及本任务 plan/history。
- 同任务 history：`docs/histories/2026-10/2026-10-22-selection-format-preservation.md`
- 用户限制：后台进行；保留轻按与按住手势、组合键保护、剪贴板流程、重新打开清空输入、原图标与近期 UI。
- 非目标：轻按 Option 翻译选区（待用户确认）；输入框手动输入文本的换行处理；富文本强调（选区为纯文本）。
- 验收标准：构建与 lint 通过；折行合并在代表性文本上只合并折行、保留结构。

## 工作计划

1. 系统提示词加入格式保留要求。
2. 新增保守的折行合并，仅用于划词类查询。
3. 独立测试代表性文本；构建、lint、安装；Review；history。

## 风险与决策

- 只依据文本判断折行：下一行以大写开头的真实续行（如专有名词）不会被合并，宁可保留换行。
- 不处理中日文折行：无空格语言难以区分有意换行与折行。
- 系统提示词被服务关闭时（`enableSystemPrompt` 为假），格式要求不会发送；DeepSeek 所在的 OpenAI 兼容服务始终发送。

## 进度

- [x] 提示词。
- [x] 折行合并与接入。
- [x] 验证、Review、history。

## 验证

- Release arm64 构建、两个变更 Swift 文件 SwiftLint strict、`git diff --check` 通过。
- 从源码抽取 `joiningWrappedLines` 的独立测试 14/14 通过：PDF 连字符折行、段落空行、项目符号与编号/字母/罗马列表、
  列表项内折行、标题、大写续行（保守保留）、缩进代码、句末标点、逗号续行、中文行、CRLF、单行、行尾空格。
- 查询文本路径复核：`ns_removeInvisibleChar` 只移除对象替换符；`removeExtraLineBreaks` 仅用于结果视图段距判断，
  不改写译文；手动输入不经过折行合并。
- Review：确认合并只作用于划词类动作（快捷键、自动划词、外部调用），列表正则不误伤 `e.g.`/`i.e.` 开头的续行；
  `etc.` 等缩写开头的续行会被保留为换行，属可接受的保守结果。
- 已备份并安装，签名指定要求、原图标、`Info.plist` 与配置保持。
- 未验证：真实模型输出对格式要求的遵循程度（取决于模型）；实际划词翻译的界面效果待用户使用确认。

## 完成条件

- 进度完成，验证如实记录，history 链接归档后的计划。
