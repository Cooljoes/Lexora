# 开发日志

当前公开版为 **0.2.1（构建 4）**。以下按开发顺序列出可核对的源码节点，时间均为北京时间。旧提交由本地保存的工程目录和 ZIP 补录；Git 提交时间记录此次整理的时间。相同版本和构建号下的改动使用独立快照标签。正式版本使用带 `v` 的标签。

| 原始快照时间 | 版本（构建） | 源码标签 | 变化 |
| --- | --- | --- | --- |
| 2026-11-25 22:30 | 0.1.0（1） | [snapshot-initial-cloud](https://github.com/Cooljoes/Lexora/tree/snapshot-initial-cloud) | 真机 Debug 和 Release 使用 CloudKit，模拟器使用本地资料库。时间取自原工程 README 的修改时间。 |
| 2026-11-25 22:44 | 0.1.0（1） | [v0.1.0](https://github.com/Cooljoes/Lexora/tree/v0.1.0) | 英文精读、系统翻译、离线词典、词条收藏、历史记录、系统分享扩展和 CloudKit 配置。 |
| 2026-11-25 23:45 | 0.1.0（1） | [snapshot-layout-preview](https://github.com/Cooljoes/Lexora/tree/snapshot-layout-preview) | 调整大字号布局与 iPad 导航。这份快照来自开发工作目录。 |
| 2026-11-25 23:55 | 0.1.0（1） | [snapshot-layout](https://github.com/Cooljoes/Lexora/tree/snapshot-layout) | 完成大字号词条与重点词布局、iPad 历史导航，将文中原句改为可展开查看。 |
| 2026-11-26 00:13 | 0.1.0（1） | [snapshot-ipa](https://github.com/Cooljoes/Lexora/tree/snapshot-ipa) | 引入 Britfone 和 CMUdict 地区读音，展示来源，支持为两种口音分别选择系统声音。 |
| 2026-11-26 07:52 | 0.1.0（1） | [snapshot-system-voice](https://github.com/Cooljoes/Lexora/tree/snapshot-system-voice) | 按口音优先选用系统默认声音，并保留手动选声和最高音质选项。 |
| 2026-11-26 07:58 | 0.1.1（2） | [v0.1.1](https://github.com/Cooljoes/Lexora/tree/v0.1.1) | 在关于页面显示版本号和构建号，主应用和分享扩展统一升至 0.1.1（构建 2）。 |
| 2026-11-26 08:37 | 0.2.0（3） | [v0.2.0](https://github.com/Cooljoes/Lexora/tree/v0.2.0) | 新增系统语音与离线 Kokoro-82M 切换，提供英式 Emma 和美式 Heart，调整词条的地区音标显示。 |
| 2026-11-26 | 0.2.1（4） | [v0.2.1](https://github.com/Cooljoes/Lexora/tree/v0.2.1) | 首次公开发行。加入可重建的示例词典、可选语音包安装脚本、开源许可和开发日志。 |

## 对照原始工程包

历史标签保留对应版本的 Swift 源码和工程设置。整理时清除了个人签名团队与 Xcode 用户状态，并排除了完整数据库、模型二进制和本地验收文件。各历史标签的 `docs/original-notes.md` 对应当时的开发说明。早期 MVP 源自保留的工程目录，其余条目可用原始 ZIP 的 SHA-256 核对。

| 原始归档 | SHA-256 |
| --- | --- |
| Lexora-0.1.0.zip（22:44） | `818a0c7133f4ea6b1e3075053ebad935e336f1baa5ea7fc75652c99b4e624a8e` |
| Lexora-界面更新.zip（23:45） | `5dda7767e00ca68062b8e6ed7fca62f2e0d91914ec2828eac09089e1015caece` |
| Lexora-界面更新.zip（23:55） | `e10b96aabfed37f0b819c0b4d75288942d9164b2ed6a44d25ef8ce60b8a5774b` |
| Lexora-发音与音标更新.zip（00:13） | `9e1ef4a272c99d2b7d714172f9e0460a55ccc0d958b62194d58659d8187beccc` |
| Lexora-系统默认语音.zip（07:52） | `5f2a9d360bc652b438db2ff256a0302ce193a782179a941c0e78f1dfc6aa7546` |
| Lexora-0.1.1-build2.zip（07:58） | `1ec7aea8b53544af7c90f123a656e4542f6f5bf8a2df71489c09353e62f4be89` |
| Lexora-0.2.0-build3.zip（08:37） | `0dcd5f568158197664c136a67067137b1bd5c0bf0406e53b1197234e4b435bc3` |
