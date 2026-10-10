# 中文文字与编码验证

曲目信息使用内置 HarmonyOS Sans SC Regular/Bold。文件取自华为官方字体包，未修改、转换或裁剪；源地址和完整专用许可见 NOTICE.txt、HarmonyOS-Sans-License.txt。`Scripts/import-harmonyos-fonts.py` 使用 SHA-256 校验并复现提取过程。

读入 `maidata.txt` 使用严格 Unicode 解码：默认 UTF-8；识别 UTF-8 BOM、UTF-16LE/BE BOM、UTF-32LE/BE BOM。先检测 UTF-32，避免误认成 UTF-16。未知传统编码、截断序列、无 BOM 的 UTF-16 以及无效字符明确报错，不猜测 GBK，也不插入替换字符。保存为 UTF-8。

「加载示例」打开内置的「晨光序曲｜中文显示测试」：曲名、作曲、谱师和源码注释均含中文，搭配本项目原创合成音频。更新后的示例使用 `Demo-Chinese-v1` 缓存；旧 Demo 和用户修改的文件不被覆盖。

测试覆盖六种 Unicode 编码、中文和日文及 emoji 元数据的 UTF-8 保存回读、损坏数据拒绝、内置字体的中文字符覆盖，以及 H.264/HEVC 导出后解码画面的中文 OCR。

生成整段中文测试谱面、原始合成音乐、两个带声音的视频与开场截图：

```sh
MAJDATA_CHINESE_DEMO_PROOF=/path/to/local/output swift test -c release --filter ChineseDemoTests
```

原版 Minimoon 不含本示例使用的中文字形，因此原实现依赖系统字体回退。原反馈具体视频尚未取得，不能将缺字、字体缓存或编码中的任一项认定为完整根因。
