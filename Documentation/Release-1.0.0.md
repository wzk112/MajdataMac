# Majdata Mac 1.0.0

首个正式 Release：面向 macOS 的原生 Simai 谱面编辑、预览、检查与视频导出工具。

## 下载哪个文件

- **macOS 26+、Apple silicon（M 系列）**：下载 `MajdataMac-1.0.0-macOS-arm64.dmg`，或 ZIP 备用包。
- 这次没有 Intel 安装包。已在 macOS 27.0.1 上验证，尚未在 macOS 26 实机复测。
- GitHub 的 `Source code` 是源码，不是可直接运行的应用。

## 安装与首次打开

1. 升级前保存谱面并退出旧版。打开 DMG，把 **Majdata Mac.app** 拖入 **Applications（应用程序）**。
2. 从「应用程序」双击启动。如果提示“Apple 无法验证此 App 是否包含恶意软件”或“无法验证开发者”，关闭提示。
3. 打开 **系统设置 → 隐私与安全性 → 仍要打开（Open Anyway）**，按系统要求认证，再确认打开。必须先尝试启动，设置中才会出现 Majdata Mac 的放行项。
4. ZIP 包使用系统归档实用工具解压后，同样拖入「应用程序」并按上述步骤打开。

**本版使用 ad-hoc 完整性签名，没有 Developer ID 分发签名，也未经过 Apple 公证。** 系统提示受 macOS 版本、已有放行记录和管理策略影响。安装包不包含关闭 Gatekeeper 或删除隔离属性的脚本。

如果显示“已损坏”，请重新从本 Release 下载、核对 `SHA256SUMS.txt`；仍然出现时请[反馈系统版本、截图和校验结果](https://github.com/wzk112/MajdataMac/issues)。不要将“已损坏”当成正常提示，也不要关闭系统安全检查。完整步骤见[安装说明](https://github.com/wzk112/MajdataMac/blob/v1.0.0/Documentation/Install.md)与 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

## 已实现

- 七个难度的 Simai 编辑、语法定位、查找替换、镜像/旋转、自动恢复和源码播放高亮。
- 可调面板；带波形、音符分类、节拍网格、缩放、吸附和双光标的时间轴。
- 原版素材、音效、42 组滑条几何及动画曲线；居中的独立宽屏舞台与谱面信息。
- Classic 自动播放；实验区域模拟及可能存在无理／撞尾的检测，可定位时间与源码。
- 九路混音、变速、循环和音频输出设备切换；判定区及烟花等画面效果可独立控制。
- 原版录制开场；最高 4K、60 fps 的 HEVC/H.264 视频，及 WAV/JSON 导出。
- Canvas 绘制结合 Metal 特效与图像转换，复用渲染结构、连续解码 PV，并使用硬件编码。

## 已知限制

- 仍有未移植的原版功能，包括手动游玩、实体控制器、完整原版设置和部分外部服务。
- 区域模拟尚未完全对齐原版 DJAuto；无理／撞尾检测提供风险提示，不保证求解所有真人打法。
- 复杂谱面可能掉帧，不保证任何机器都持续达到 120 Hz。
- iShot / 虚拟声卡的实际录音效果仍需对应设备验证。

## 来源与许可

GNU GPL v3。主要移植来源为 [MajdataView](https://github.com/LingFeng-bbben/MajdataView) 和 [MajdataEdit](https://github.com/LingFeng-bbben/MajdataEdit)，判定区域几何来自 [MajdataPlay](https://github.com/TeamMajdata/MajdataPlay)。[MaiMuriDX](https://github.com/Minepig/MaiMuriDX) 与 [maimaiMuriDetector](https://github.com/Moying-moe/maimaiMuriDetector) 用作研究参考，未复制 MaiMuriDX 代码或素材。详见 [NOTICE](https://github.com/wzk112/MajdataMac/blob/v1.0.0/NOTICE.txt)。本项目独立维护，与 SEGA 或 TeamMajdata 无隶属关系。
