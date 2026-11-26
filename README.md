# Lexora

**0.2.1（构建 4）** · 原生 iPhone / iPad 英语精读应用 · iOS / iPadOS 26.0 及以上

粘贴或分享一段英文，即可查看全文译文、点词查询语境释义、英美音标和词源，并收藏生词。词条链接到数据来源。SwiftUI 界面支持 iPad 分栏、大字号和深色模式。

## 从源码运行

1. 用 Xcode 打开 `Lexora.xcodeproj`，选择 `Lexora` scheme 和 iPhone 或 iPad 模拟器，按 ⌘R。开发时使用 Xcode 27.2、Swift 6.4.2 和 iOS SDK 27.2。
2. 在书桌选择「经典选读」，或在「生词本」搜索 `hospital`、`record`、`endless`。公开版自带 151 个有释义的示例词头，也可试查只有读音的 `daylight`。中文和英文 Wiktionary 的释义保留原文。
3. 真机运行时，为主应用和分享扩展选择自己的开发团队，将工程级 `LEXORA_BUNDLE_ID` 改为自己的唯一标识，并确认 App Group 匹配。Debug 使用本地资料库。Release 的跨设备同步需要有相应权限的团队、自有 CloudKit 容器和推送配置。

全文翻译使用 Apple Translation。首次使用时系统可能提示下载英译简中语言包，完整翻译流程需要在支持的真机上验证。

## 发音

默认可直接使用设备的英式或美式系统声音。要启用离线 AI 发音，在工程根目录执行下面的命令，完成后重新构建 App。

```sh
python3 Tools/fetch_voice_pack.py
```

脚本通过 HTTPS 从固定版本获取 Kokoro Core ML 模型和发音数据并校验散列。资源随 App 安装后可断网运行。在「设置 → 单词发音」选择「AI 语音包」，英式为 Emma，美式为 Heart。已安装的完整语音包约 95 MiB。[语音包来源与许可](KokoroVoicePack/SOURCES.txt)

## 代码和数据

| 路径 | 内容 |
| --- | --- |
| App、Core | SwiftUI 界面、NaturalLanguage 分析、SQLite 查询、Apple 翻译、SwiftData 和 Core ML 发音 |
| Shared、ShareExtension | 跨进程收件箱和系统分享扩展 |
| Resources | 示例词典、音标来源说明、图片和隐私清单 |
| Tools | 词典重建、英美参考读音导入和可选语音包安装脚本 |
| Tests、UITests | 核心逻辑、存储、语音合成和界面回归测试 |

在 Xcode 中按 ⌘U 运行测试。要运行真实 Kokoro 合成测试，先准备语音包。工程自带 Xcode 工程文件，调整工程结构时可用 XcodeGen 从 `project.yml` 重新生成。

每次交付同时更新版本号和构建号。主应用与分享扩展使用同一组编号，可在「设置 → 关于与数据来源」查看已安装的版本。

[开发日志与旧版源码](CHANGELOG.md) · [示例词典重建方法](docs/dictionary.md) · [原创代码 MIT 许可](LICENSE) · [第三方资料与素材](THIRD_PARTY_NOTICES.md)
