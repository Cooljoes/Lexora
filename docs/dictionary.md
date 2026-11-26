# 离线词典

Lexora 0.3.0 内置 **71,105 个有释义的英文词头**。另有 99,214 种拼写只收录了地区参考读音。下载工程即可离线查词。释义、词形和词源保留源词典的记录。[数据许可与来源](../THIRD_PARTY_NOTICES.md)

| 随应用安装的数据 | 数量 |
| --- | ---: |
| 有释义的词头 | 71,105 |
| 收录中文版 Wiktionary 条目的词头 | 59,697 |
| 收录英文版 Wiktionary 条目的词头 | 17,730 |
| 条目记录 / 义项 | 100,972 / 198,413 |
| 词形与原形的对应关系 | 49,752 |
| 收录词源 / 构词记录的词头 | 21,364 / 7,486 |
| 有释义且可查英、美两地音标的词头 | 17,247 |
| Britfone、CMUdict 的地区参考读音记录 | 151,339 |

同一词头可能在中、英两版 Wiktionary 均有条目。地区读音可能有多个变体。App 在词条中标明各项资料的来源，CMUdict 的 ARPAbet 音素按工程内的映射转写为宽式 IPA。[发音来源与转写说明](../Resources/Pronunciation-Licenses.txt)

## 如何选词

1. 从中文版 Wiktionary 的快照导入有释义的英语条目，收录小写拉丁字母组成的拼写，并允许词内使用连字符和撇号。
2. 对阅读词表中的 18,808 个候选拼写，再从英文版 Wiktionary 导入有来源的释义、词形、音标和词源。候选包括原版自编词表、现代阅读补充词、Britfone 的拼写，以及 Simple English Wiktionary 中至少有一个义项同时提供释义和用例的词。拼写会去重，有释义的候选才进入释义词库。对已有释义的词头，也会索引英文版收录的屈折词形。[固化的阅读词表](../Tools/reading-headwords.txt) · [选择规则](../Tools/select_reading_headwords.py)
3. 完整导入固定版本的 Britfone 和 CMUdict 读音索引，供词条按英式和美式分别查阅。[Britfone 和 CMUdict 的许可](../Resources/Pronunciation-Licenses.txt)

## 重建数据库

将下表前两份压缩包按下载时的原名放在仓库根目录。上游定期更新，SHA-256 用于确认本版快照。公开仓库已保留选词结果，从该清单重建词库只需前两份快照。

| 原始快照 | SHA-256 |
| --- | --- |
| [英文版 Wiktionary](https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl.gz) | `4d03b6cba283744756c57ff661c2c6cbfe34fcf8ff513a966576cf7d97e91a99` |
| [中文版 Wiktionary](https://kaikki.org/dictionary/downloads/zh/zh-extract.jsonl.gz) | `30f175aa641b204c43755e942a6e97d38cf5e93d7815ce1e2475e68c068b82c0` |
| [Simple English Wiktionary 选词用快照](https://kaikki.org/dictionary/downloads/simple/simple-extract.jsonl.gz) | `79afd871e342db3b87c3f2044ed21efa312e4c4ee006814b57c4cf4536ef70a1` |

在仓库根目录执行以下命令，选择一个尚未存在的数据库文件名。读音导入脚本会按固定提交下载并校验两个上游文件。已有这些文件时，追加 `--sources <目录>` 即可离线执行。

```sh
python3 Tools/build_dictionary.py kaikki.org-dictionary-English.jsonl.gz zh-extract.jsonl.gz Tools/reading-headwords.txt rebuilt.sqlite --all-chinese
python3 Tools/import_pronunciations.py rebuilt.sqlite
sqlite3 -readonly rebuilt.sqlite "PRAGMA integrity_check; SELECT value FROM metadata WHERE key='headwords';"
shasum -a 256 rebuilt.sqlite
```

完整性检查应输出 `ok`，词头数为 `71105`。随包数据库为 72,069,120 字节，SHA-256 为 `71b5e54363e5377c84031c6fdb2084a071c395ef8d09376fc6506679539170e3`。如需复核选词过程，再下载表中第三份快照，生成阅读清单并与仓库版本逐字节比较。

```sh
python3 Tools/select_reading_headwords.py simple-extract.jsonl.gz > reading-headwords.txt
cmp reading-headwords.txt Tools/reading-headwords.txt
```

随库清单的 SHA-256 为 `47baefa10aa87a5dc19186505830affd29ffd0f5ecd56902ca2ba838d76d996c`。[Simple English Wiktionary](https://simple.wiktionary.org/) · [Kaikki 快照说明](https://kaikki.org/dictionary/rawdata.html)
