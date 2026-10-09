# Majdata Mac 1.0.0 安装说明

支持 macOS 26 及以上、Apple silicon（M 系列）。本次没有 Intel 安装包。

官方下载：https://github.com/wzk112/MajdataMac/releases/latest

## 安装

1. 下载 `MajdataMac-1.0.0-macOS-arm64.dmg`，打开后把 `Majdata Mac.app` 拖入 `Applications`（应用程序）。升级前先保存谱面并退出旧版。
2. 从「应用程序」双击 Majdata Mac。如果出现“Apple 无法验证此 App 是否包含恶意软件”或“无法验证开发者”，关闭提示。
3. 打开「系统设置 → 隐私与安全性」，向下找到 Majdata Mac，点击「仍要打开（Open Anyway）」。按系统要求输入密码或使用 Touch ID，再确认打开。
4. 必须先尝试启动，设置中才会出现这一项；首次确认后通常无需重复操作。单位或学校管理的 Mac 可能不允许自行放行。

也可以下载 ZIP，使用 macOS 自带的归档实用工具解压，将 App 拖入「应用程序」后按上述步骤打开。GitHub 自动提供的 `Source code (zip/tar.gz)` 是源码，不是安装包。

## 签名和安全提示

本版使用 ad-hoc 签名校验 App 内容完整性，没有 Developer ID 分发签名，也未经过 Apple 公证。ad-hoc 签名不提供开发者身份认证。

安装包不包含关闭 Gatekeeper、删除隔离属性或修改系统安全设置的脚本。请使用系统提供的单个 App 放行方式，不需要关闭整台 Mac 的安全检查。不同系统版本、已有放行记录和设备管理策略会影响提示，本机验证不代表所有 Mac 均已验证。

Apple 官方说明：https://support.apple.com/zh-cn/102445

如果提示“已损坏”，不要将它视为正常安装提示，也不要盲目放行或运行修复命令。请重新从本仓库下载，核对 SHA-256 校验值；仍然出现时，提交系统版本、提示截图和校验结果：
https://github.com/wzk112/MajdataMac/issues

如果提示“会损坏你的电脑”或检测到恶意软件，请停止运行并报告，不要绕过该提示。

## 可选：核对下载文件

Release 提供 `SHA256SUMS.txt`，可对照本地文件的 SHA-256：

```sh
shasum -a 256 ~/Downloads/MajdataMac-1.0.0-macOS-arm64.dmg
```

校验值必须与同一 Release 的 `SHA256SUMS.txt` 完全相同。它用于确认下载内容是否一致，不代替 Apple 公证。

## 首次使用

通过「文件 → 加载示例」查看内置谱面，或按 ⌘O 打开自己的 `maidata.txt` / 谱面文件夹。同目录可放音乐、背景图片和 PV。Release 不含用户下载的歌曲、谱面或录像。

常用快捷键：⇧⌘C 播放/暂停，⇧⌘P 独立舞台，⇧⌘M 九路混音器，⌘S 保存。

默认 Classic 自动播放直接给予最高判定。检查页对可能存在无理／撞尾的提示来自区域模拟，不是机台成绩或真人可行性的最终判决。
