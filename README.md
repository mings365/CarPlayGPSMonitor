# CarPlay GPS Monitor（iPhone GPS 来源检测）

不需要本地 Mac：GitHub Actions 使用 macOS 云端 Runner 编译 unsigned IPA，随后用 Windows 上的 Sideloadly 或 AltStore 进行签名与安装。

## 上传并编译

1. 在 GitHub 新建仓库（公开仓库通常更适合免费 Actions），不要上传实际 GPS 日志。
2. 将 **此文件夹内所有文件** 上传到仓库根目录（必须保留 `.github/workflows/build-ipa.yml` 目录结构；直接在 GitHub 网站上传 ZIP 文件本身不会自动解压）。
3. 在仓库 **Actions → Build unsigned iPhone IPA → Run workflow** 手动启动；或者推送到 main 分支自动触发。
4. 等任务成功后，进入运行详情，在 **Artifacts** 下载 `CarPlayGPSMonitor-unsigned-IPA`，解压得到 `CarPlayGPSMonitor-unsigned.ipa`。
5. Windows 上安装 Sideloadly（https://sideloadly.io/）或 AltStore Classic（https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows），用个人 Apple ID 签名 IPA 并通过 USB 安装到 iPhone；必要时在 iPhone 设置中开启开发者模式并信任开发者。

## 测试

1. iPhone 独立导航时，在测试 App 选“手机独立”，允许精确位置并点“开始”；保持屏幕点亮、App 在前台。采集几分钟并停止。
2. 切换到“有线CarPlay”，连接并采集；再选择“无线CarPlay”采集。每种模式可以分开运行，**不要清空**，记录会合并进一个 CSV。
3. 点“导出CSV”，选择“存储到文件”。保存后退出 App；否则日志可能丢失。
4. 比较 `source=EXTERNAL`、`NON_EXTERNAL`、`UNKNOWN` 在不同模式中的数量与连续性。

## 重要限制

- `isProducedByAccessory=false` 只代表“非外部设备来源”，**不等于保证来自 iPhone GNSS 芯片**。
- Apple 的 Core Location 不保证在 CarPlay 下同时提供两个独立定位流。
- 此 App **不会**改变导航 App 的 GPS 来源，也不是 CarPlay 屏幕上的导航应用。
- 只测试前台定位，不申请后台定位能力。开车时交由乘客操作；不要驾驶时触碰设备。
- 只在导出时持久保存 CSV；测试日志包含敏感经纬度，切勿提交到公开 GitHub 仓库。
- 此项目未在本地 macOS/Xcode 环境实编译（当前执行环境没有 Xcode）；GitHub Actions 运行记录才是最终构建验证。
