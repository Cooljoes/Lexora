> 早期本机工程说明。本标签供查看旧源码和原始开发记录。

# Lexora

Lexora 是一款英译简中的原生精读应用，支持 iOS 26.0 和 iPadOS 26.0 及以上版本。直接打开同目录的 Lexora.xcodeproj，选择 Lexora scheme 和 iPhone 或 iPad 运行。词典和插图均已随工程提供。首次构建无需联网下载依赖。

## 使用

- 在书桌点「粘贴英文」，直接阅读剪贴板中的句子或段落。也可以点「输入原文」修改后再开始。单次支持 12,000 个字符。
- 阅读页自动分析原文。点正文里的任一英文词或下方的重点词，查看语境候选释义、单词所在原句、地区音标、构词与词源。通过「查看其他释义」切换义项，通过书签按钮收藏。发音来自系统语音合成。
- 语言资源齐备的真机自动完成全文翻译，保留换行并保存译文。首次使用可能出现 Apple 的语言包下载确认。翻译失败时可重试，已保存的译文可离线阅读。
- 在其他应用中选中英文纯文本，打开系统分享菜单，选择「Lexora」或「存入 Lexora」。在扩展内确认后，打开主应用即可在历史中找到原文。若分享菜单仅传入网页地址，应先选中网页里的英文。
- 「生词本」顶部可直接查离线词典。「历史」支持搜索，左滑记录可删除。书桌右上角可查看数据来源、许可及隐私说明。

## 工程

| 目录 | 用途 |
| --- | --- |
| App | SwiftUI 书桌、精读、词条、生词本、分享入口、资料库和翻译 |
| Core | NaturalLanguage 分析、SQLite 查词和语境排序、分段、SwiftData 模型 |
| Shared、ShareExtension | 共享收件箱和系统文字分享扩展 |
| Resources | 只读词典、CC BY-SA 许可、图片资源和隐私清单 |
| Tests、UITests | 在真实框架及随包数据库上运行的 XCTest 与 XCUITest |
| Tools | 可复现的 SQLite 词库生成器 |

已生成的 .xcodeproj 可直接使用。只有更改工程结构时才需要使用 XcodeGen 2.44.1 运行 `xcodegen generate`。准备自己的签名时，在两个 target 选择相同的开发团队。配置正式的 LEXORA_BUNDLE_ID、LEXORA_APP_GROUP 和 LEXORA_CLOUD_CONTAINER，并创建相应标识和描述文件。主应用使用 iCloud/CloudKit、Push Notifications、Background Modes 的 Remote notifications 和 App Groups，扩展使用同一 App Group。

模拟器的 SwiftData 持久化在本地；真机构建显式指定 CloudKit 私有数据库。每个模型字段有默认值，没有唯一性约束。分享扩展先原子写入独立文件，主应用成功保存 SwiftData 后才移除文件，重复处理同一分享 ID 不会创建第二条历史。云端同步的账户状态与每一条记录的实际同步结果是两个不同的状态。

## 词典数据

来源为中文及英文 Wiktionary 贡献者撰写的英文条目，由 Kaikki.org 使用 Wiktextract 提取。离线数据库沿用 CC BY-SA 4.0。作品修改包括词头筛选、结构化、义项数量上限、地区标签归类、构词模板提取和索引。保留来源语言与字形，释义可能为英文或繁体中文。每个词条提供指向原版 Wiktionary 页面的署名与查询入口，可从条目历史查看贡献者。系统翻译、系统发音与词典来源分别标注。

| 本版覆盖 | 词头数 |
| --- | ---: |
| 全库 | 30,798 |
| 含中文来源 | 24,690 |
| 至少一个来源条目同时标注英式与美式 IPA | 6,614 |
| 有词源文本 | 18,849 |
| 有明确构词记录 | 11,591 |

一个词头可能包含多个词性、语源或义项。音标不跨地区推导，未分地区的 IPA 单独显示。缺失的词源、地区音标和构词分析会在界面中明确提示。启发式语境排序根据词性和词典释义、例句的词汇重叠判断，用户可以在候选中自行选择。系统标注缺失时使用随包收录的词形索引，包括 33,404 条词形关系。

数据下载地址及本次输入文件的 SHA-256 如下。Kaikki 的链接随上游更新，以散列识别本版输入。重建时使用匹配的快照；新的快照会改变覆盖数字及数据库内容。

| 输入 | SHA-256 |
| --- | --- |
| [英文版 English JSONL gzip](https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl.gz) | 4d03b6cba283744756c57ff661c2c6cbfe34fcf8ff513a966576cf7d97e91a99 |
| [中文版 Wiktextract JSONL gzip](https://kaikki.org/dictionary/downloads/zh/zh-extract.jsonl.gz) | 30f175aa641b204c43755e942a6e97d38cf5e93d7815ce1e2475e68c068b82c0 |
| [词头筛选用的常用词清单](https://raw.githubusercontent.com/first20hours/google-10000-english/d0736d492489198e4f9d650c7ab4143bc14c1e9e/google-10000-english.txt) | 9c965d384526facc59260e94f8ccff1582633fa385004abe1455ed457062acbc |

```shell
python3 Tools/build_dictionary.py en.jsonl.gz zh.jsonl.gz common.txt rebuilt.sqlite
sqlite3 rebuilt.sqlite 'PRAGMA integrity_check'
```

随包数据库的 SHA-256 为 `54e0beb6c6f4f43fc88a44344aec1adc8b70d85fcfece6fa8521e19f6d8efc08`。词典许可全文在 Resources/CC-BY-SA-4.0.txt。经典选读采用达尔文 1859 年初版《物种起源》第 490 页公版原文。植物封面为生成插画。[Kaikki](https://kaikki.org/dictionary/rawdata.html) · [Wiktextract](https://github.com/tatuylonen/wiktextract) · [词典许可](https://creativecommons.org/licenses/by-sa/4.0/) · [Darwin Online 原文](https://darwin-online.org.uk/Variorum/1859/1859-490-dns.html)

## 测试与发布

在 Xcode 中按 ⌘U 或在项目目录执行下列命令。将设备名称替换为本机可用模拟器。

```shell
xcodebuild -project Lexora.xcodeproj -scheme Lexora -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -parallel-testing-enabled NO test
```

Apple Translation 的系统语言包流程需要受支持的真机。正式测试需覆盖首次下载、取消、断网、成功翻译、重开后读取缓存，以及已下载系统语音的发音试听。已附真机集成测试 testInstalledAppleTranslationOnDevice。安装英译简中语言包后在真机运行测试，可调用生产翻译代码并检查双段中文输出。CloudKit 端到端验收需用同一 iCloud 账户的两台设备交叉新增、收藏、删除并检查收敛，发布前将 Development Schema 部署到 Production。[Apple Translation](https://developer.apple.com/videos/play/wwdc2024/10117/) · [SwiftData 与 CloudKit](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)

发布还需配置分发签名，在 App Store Connect 填写商品页、支持和隐私政策 URL、年龄分级及隐私披露，再通过 TestFlight 验收并送审。[审核指南](https://developer.apple.com/app-store/review/guidelines/) · [隐私政策要求](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/)

## 本次验收

本机环境为 Xcode 27.2、Swift 6.4.2、iOS SDK 27.2。iPhone 18 Pro 在 iOS 27.0 模拟器上分批通过 7 项核心测试与 5 项界面测试，其中分享扩展冷启动等待条件经修正后单独回归通过。iPad Pro 11 英寸（M5）在深色横屏下完整通过同样 12 项测试，零失败、零跳过。iPad 首次查询系统语音资源曾阻塞界面，已将语音操作移到后台，并验证点击发音后可立即收藏与关闭词条。

新工作目录内的工程已通过通用 iOS 设备 Release 归档。已核对主应用、嵌入的分享扩展均为 arm64，词典散列与随包资源一致。归档使用 CODE_SIGNING_ALLOWED=NO。详细测试批次、重试和待验收项目见同目录的「验证记录.json」。
