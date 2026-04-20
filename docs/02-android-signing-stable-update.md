# Android 升级安装签名不一致说明（免费方案）

## 你现在遇到的问题

`安装失败(-7)` + `与已安装应用签名不同`，不是小米流程问题，而是 Android 的标准校验。

仓库当前 Android 打包流程会在临时 GitHub Runner 上动态创建 `android/` 平台文件，并使用 `signingConfigs.debug`。  
如果 `~/.android/debug.keystore` 每次都新生成，签名指纹就会变化，导致“可更新但更新失败”。

## 是否随机签名

结论：在当前流程下，签名有概率每次变化。  
因为 Runner 是临时环境，默认 debug keystore 不是长期固定保存。

## 免费且可长期稳定的方案

已新增两部分工作流：

1. `bootstrap-android-debug-keystore`  
用途：一键生成一个可长期复用的免费 keystore（自签名）。
2. `build-and-release-android-packages`  
用途：每次构建前从仓库 Secret 恢复同一个 keystore，保证签名一致。

## 一次性初始化步骤

1. 在 GitHub Actions 手动运行 `bootstrap-android-debug-keystore`。
2. 下载产物 `android-debug-keystore-secret`。
3. 打开其中的 `ANDROID_DEBUG_KEYSTORE_BASE64.txt`，复制整行文本。
4. 进入仓库 `Settings -> Secrets and variables -> Actions`。
5. 新建 Repository Secret：
`ANDROID_DEBUG_KEYSTORE_BASE64` = 刚复制的整行 Base64。
6. 重新运行 `build-and-release-android-packages`。

## 关于当前手机里的旧版本

如果手机里已安装版本不是同一把密钥签名，第一次仍然无法覆盖安装。  
需要先卸载一次旧包，再安装新包。  
从这次开始，只要一直复用同一个 Secret，以后就能正常升级覆盖。

## 边界说明

这是“免费自签名 + 稳定覆盖安装”方案，适合测试分发和私有分发。  
若将来要上 Google Play，再升级到正式发布签名流程即可。
