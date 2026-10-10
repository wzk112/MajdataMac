# 发布流程

发布时同步 `Scripts/build-app.sh` 的版本/build、README、README.txt、NOTICE、CHANGELOG、安装说明和功能核对的当前版本。历史版本记录保留。App 设置和系统“关于”面板读取 Info.plist。

## 构建与校验

```sh
swift test -c release
./Scripts/build-app.sh release
./Scripts/package-release.sh
```

必须检查测试退出状态和完整结果。音频回归使用静音输出；外部谱面和长视频测试依赖环境变量，不能将未启用的测试当作真实谱面已经复测。包脚本严格验证 App 签名，解压 ZIP、挂载 DMG，再比较每个 App 文件与构建副本的 SHA-256。输出在 `dist/release-版本号/`；已有目录不会被覆盖。

默认仅打包 arm64。若以后发布 Intel 或 Universal，先更新构建与打包脚本并完成对应机器验证，不能只改文件名。

## 签名

默认 ad-hoc 签名只是完整性校验，不能称为 Developer ID 签名或 Apple 公证。macOS 的 `syspolicy_check distribution` / `spctl --assess` 因未公证拒绝，不能写成“Gatekeeper 自动放行通过”。

可使用 `CODESIGN_IDENTITY` 传入自己的 Developer ID Application 身份，脚本开启 hardened runtime 和安全时间戳。Apple Development 证书不是公开分发证书。取得合适身份后另行使用 `notarytool` 公证、`stapler` 附加票据并验证，之后再打包。所有资源修改必须在签名前完成；修改签名后的 App 会破坏完整性。

首次打开流程应使用真实下载包验证，并记录系统版本、隔离属性、系统提示及是否存在「仍要打开」。开发机器上已有信任记录、没有隔离属性的本地启动、纯 codesign 验证，都不能证明其他 Mac 的 Gatekeeper 行为。不要为测试关闭全局 Gatekeeper 或静默移除下载隔离属性。

## GitHub Release

1. 检查 `git diff --check`，将源码和文档提交至修复分支，通过 PR 审查和回归后合并到 main；发布以合并后的提交为准。
2. 创建与准确提交对应的版本标签；先建立 draft Release，上传 DMG、ZIP、INSTALL.txt、SHA256SUMS.txt。
3. 下载 draft 资产，核对所有 SHA-256，解压或挂载检查签名、架构、最低系统版本和资源。
4. Release 正文写明系统/芯片要求、首次打开步骤、签名/公证状态、功能和已知限制。
5. 发布为非 prerelease，设为 Latest；再次读取远端正文、标签、资产大小和哈希。

不要上传用户谱面、歌曲、视频、调试日志、证书、私钥或本地缓存。公开 Release 不等于“没有任何 bug”或“所有原版功能均已移植”。
