# 示例词典

公开版本的 `Resources/Dictionary.sqlite` 包含 151 个词头、579 条按词性与词典版本区分的条目、513 条词形关系和 351 条地区音标记录。选词范围来自自编的阅读词表、内置达尔文选段和工程测试。词表可直接审查和修改。[选词清单](../Tools/starter-headwords.txt)

## 复现

首次构建 App 直接使用随仓库提交的数据库。如果需要重建，先从 Kaikki 下载英文版和中文版 Wiktextract JSONL 压缩文件。链接指向持续更新的数据，下面的 SHA-256 标识本次构建所用的历史版本。

| 原始数据 | SHA-256 |
| --- | --- |
| [英文版](https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl.gz) | `4d03b6cba283744756c57ff661c2c6cbfe34fcf8ff513a966576cf7d97e91a99` |
| [中文版](https://kaikki.org/dictionary/downloads/zh/zh-extract.jsonl.gz) | `30f175aa641b204c43755e942a6e97d38cf5e93d7815ce1e2475e68c068b82c0` |

从仓库根目录运行以下命令，目标使用新的文件名。最后一行应输出 `ok`。

```sh
python3 Tools/build_dictionary.py en.jsonl.gz zh.jsonl.gz Tools/starter-headwords.txt rebuilt.sqlite
python3 Tools/import_pronunciations.py rebuilt.sqlite --headwords-only --extra-word daylight
sqlite3 rebuilt.sqlite 'PRAGMA integrity_check'
```

导入脚本从固定提交校验并读取 Britfone 和 CMUdict，对有明确地区的读音建索引。CMUdict 的 ARPAbet 按公开脚本转写为 IPA。词形、释义、词源和音标保留对应的来源。当前随包数据库 SHA-256 为 `8c1e381f62c7b516963ba6a824dc8fb0925e4894274be84314552e5271d49577`。采用其他快照或工具版本可能改变输出。[词典许可](../Resources/CC-BY-SA-4.0.txt) · [地区音标许可及来源](../Resources/Pronunciation-Licenses.txt)
