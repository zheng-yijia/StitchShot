# StitchShot 构建说明

对标 Picsew 的 iOS 长截图与拼图工具。当前进度：**Phase 0–6 全部完成**（拼接引擎、滚动截图、图片编辑器、Safari 整页快照、Share/Action 扩展、URL Scheme 自动化、App Intents、控制中心、StoreKit 2 Pro 内购），另含**视频转实况照片**（对标 IntoLive）。

## 前置条件

- macOS + Xcode 15 或更高版本（控制中心控件需 Xcode 16+ 的 iOS 18 SDK，旧 SDK 会自动跳过该控件）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- Apple Developer 账号（免费账号即可真机调试，但 App Group 与多扩展需要付费账号的 Provisioning 能力）

## 无 Mac 验证：GitHub Actions CI

仓库自带 `.github/workflows/ios-ci.yml`，push 到 GitHub 后自动运行，**公开仓库免费**（私有仓库消耗账号 Actions 分钟数，macOS 按 10 倍计）：

| Job | Runner | 内容 |
|---|---|---|
| js-tests | ubuntu | Safari 扩展 JS 单测 + Swift 静态审计（`scripts/`） |
| macos-build-test | macos-15 | xcodegen 生成工程 → 免签名编译全部 6 个 Target → 在 iOS 模拟器跑 StitchKit 四个 Swift 单测 Target（含 LivePhotoKit 的实况照片元数据断言） |

- 无需任何 secrets 或开发者账号（模拟器构建免签名）。
- 编译失败或单测失败时，在 Actions 页面下载 `test-results` artifact（xcresult）查看详情。
- Runner 镜像更新导致模拟器/Scheme 名漂移时，脚本会自动探测可用的 iPhone 模拟器与包测试 Scheme，一般无需改动。

## URL Scheme 自动化（对标 Picsew）

```
stitchshot://x-callback-url/vert?in=clipboard&out=save&clean_status=1
stitchshot://x-callback-url/hori?in=latest&count=3&out=clipboard&delete_source=1
stitchshot://x-callback-url/scroll        （打开滚动截图页，录屏需手动）
```

参数：

| 参数 | 取值 | 说明 |
|---|---|---|
| in | clipboard（默认）/ latest | 图片来源：剪贴板 / 相册最新 N 张截图（count=2~30，默认 2） |
| out | save（默认）/ clipboard / x-callback-url | 输出：存相册 / 复制到剪贴板 / 复制到剪贴板并回调 x-success |
| delete_source | 0/1 | 完成后删除相册源截图（仅 in=latest） |
| mockup | 0/1 | 结果套设备外壳 |
| clean_status | 0/1 | 拼接前逐张清理状态栏 |
| x-success / x-error | URL | 完成 / 失败回调（x-error 附 errorCode、errorMessage） |

快捷指令（iOS 16+ 自动出现在 Shortcuts App）：拼接最新截图 / 拼接图片 / 打开滚动截图。
控制中心（iOS 18+）：添加「滚动截图」控件一键进入录屏拼接。

## 视频转实况照片（对标 IntoLive）

工具页 →「视频转实况照片」：从相册选视频 → 拖滑杆截取片段（≤ 5 秒）→ 可选「直接截取 / 来回循环」（Boomerang）→ 转换 → 长按预览 → 保存到相册。

实现要点（`Packages/StitchKit/Sources/LivePhotoKit`）：

- 输出一对资源：`still.jpg`（封面帧 + Apple Maker Note `{17: identifier}`）与 `video.mov`（H.264 + `mdta` content identifier + still-image-time 元数据轨道），保存进相册即为系统原生实况照片
- 一律重编码 H.264（丢音频），方向由视频轨 `preferredTransform` 保留
- 来回循环为 正放 + 倒放折返（首尾不重复），帧数以 JPEG 中间态控制在 120 帧内
- 转换在后台线程执行；保存后自动清理临时文件
- 单测覆盖：资源对生成、JPEG 魔数与 maker note、content identifier、元数据轨道、时长夹取、非法范围报错

模拟器与真机均可测（保存到模拟器相册后可用系统照片 App 长按预览）；无网络/无账号要求。

## Pro 内购配置（StoreKit 2）

### 本地测试（无需任何开发者账号）

仓库自带 `Configuration/StitchShot.storekit`（StoreKit Configuration 文件，产品 ID `com.example.stitchshot.pro` 与 `App/Services/ProUpgradeManager.swift` 一致）：

1. Xcode 顶部 scheme 菜单 → Edit Scheme… → Run → Options → **StoreKit Configuration** → 选择 `StitchShot.storekit`
2. 之后在模拟器或真机上「设置 → Pro」即可完整测试购买、恢复购买、退款/撤销回落，全程不经过 App Store
3. 注意：`.xcodeproj` 由 XcodeGen 生成，每次重新 `xcodegen generate` 后需重新选择该文件

### 上线配置（需要付费开发者账号）

1. App Store Connect → 你的 App → 功能 → App 内购买项目 → 创建**非消耗型**项目，产品 ID：`com.example.stitchshot.pro`（如修改请同步代码）。
2. 沙盒测试：设置 → App Store → 沙盒账户登录后，在 App 内「设置 → Pro」购买/恢复。
3. 买断制解锁：带壳截图、自动化 mockup 参数；未购买时点启用会弹出升级页。

## 发布前清单（TestFlight / 上架）

- [ ] `xcodegen generate` 后 6 个 Target 全部签名通过，App Group 一致
- [ ] 真机验证：多截图拼接（含接缝微调）、滚动截图全流程、编辑器七工具、Safari 整页快照、Share/Action 导入收件箱
- [ ] 视频转实况照片：转换后在系统照片 App 长按预览，确认动态效果与封面帧正常（截取与来回循环各测一次）
- [ ] 快捷指令三个 Intent 出现且可运行；iOS 18 设备控制中心可添加「滚动截图」
- [ ] URL Scheme 自动化：`vert?in=latest&count=2&out=save` 冒烟测试
- [ ] 本地 `StitchShot.storekit` 全流程：购买 → 权益解锁 → 恢复 → 撤销回落；再用沙盒账号复核
- [ ] iPad 各页面单栏栈式导航显示正常
- [ ] App Store 截图与隐私清单（照片读写、无数据收集）

## 生成工程

本仓库不包含 `.xcodeproj`（由 XcodeGen 声明式生成，避免手写 pbxproj 出错）：

```bash
cd Pic
xcodegen generate
open StitchShot.xcodeproj
```

每次修改 `project.yml` 后重新执行 `xcodegen generate`。

## 首次配置（必须）

1. **修改 Bundle ID 前缀**（当前为占位 `com.example.stitchshot`）：
   - `project.yml` 顶部 `bundleIdPrefix`
   - 全局替换 `group.com.example.stitchshot`（project.yml 各 target 的 entitlements、`Packages/StitchKit/Sources/StitchCore/AppConstants.swift`）
   - `App/Views/ScrollCaptureView.swift` 中的 `broadcastExtensionBundleID`
   - 然后重新 `xcodegen generate`
2. **签名**：在 Xcode 中选中 StitchShot 工程 → 每个 Target → Signing & Capabilities → 选择你的 Team。XcodeGen 已设置 `CODE_SIGN_STYLE: Automatic`。
3. **App Group**：在开发者后台或通过 Xcode 的 Signing & Capabilities 为全部 6 个 Target 勾选同一个 App Group（entitlements 文件已声明，自动签名会尝试自动创建；若失败请先在 [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list/applicationGroup) 手动注册）。
4. 选择 `StitchShot` scheme，连接真机或模拟器运行。

## 免费 Apple ID 真机调试（无付费开发者账号）

没有 Mac 时可先靠 GitHub Actions CI（见上文）完成编译与单测验证；租一台云 Mac（MacinCloud / Scaleway，按小时计费）即可用**免费 Apple ID** 把 App 装到自己的 iPhone 上：

1. Xcode → Settings → Accounts → `+` 登录任意 Apple ID（自动生成 "Personal Team"）
2. 按「首次配置」把 `bundleIdPrefix` 与 App Group 改成你的唯一前缀（免费账号自动签名要求全局唯一，`com.example.*` 会冲突）
3. 6 个 Target → Signing & Capabilities → Team 全部选你的 Personal Team；App Group 勾选同一容器（免费账号支持 App Group，自动签名会注册容器；若个别 Target 报错，重选 Team 让 Xcode 重新生成描述文件）
4. 真机运行后首次启动前：设备上 设置 → 通用 → VPN与设备管理 → 信任你的开发者证书
5. 内购测试用上一节的 `StitchShot.storekit` 本地配置，无需 App Store Connect

免费账号的限制：

- 证书 **7 天**过期，到期后在 Xcode 重新 Run 即可
- 最多同时签名 3 个 App ID；每周最多注册 10 个
- 无 TestFlight、不能创建 App Store Connect 内购（本地 `.storekit` 已覆盖内购流程测试）
- **滚动截图（Broadcast 扩展）只能真机测**，模拟器没有系统录屏广播选择器；Safari 扩展、Widget/控制中心、快捷指令、URL Scheme、视频转实况照片模拟器均可测

## Target 一览

| Target | 类型 | 作用 |
|---|---|---|
| StitchShot | 主 App | 拼接首页、滚动截图引导、工具、设置 |
| StitchShotBroadcast | Broadcast Upload Extension | 滚动截图：接收系统录屏帧并增量写入条带 |
| StitchShotShare | Share Extension | 从分享表单接收图片存入共享收件箱 |
| StitchShotAction | Action Extension | 从相册"操 作"菜单直接处理单张图片 |
| StitchShotWidgets | Widget Extension | 桌面快捷入口 + 控制中心控件（iOS 18+） |
| StitchShotSafari | Safari Web Extension | 网页快照：整页逐屏截取 + 单屏捕获 |

代码结构：

```
App/                  主 App（SwiftUI）
Packages/StitchKit/   本地 Swift 包：StitchCore / PhotoLibraryKit / StitchEngine / ScrollCaptureKit / ImageEditorKit / LivePhotoKit
Extensions/           五个系统扩展
```

## 常见问题

- **Safari 扩展 Target 报错**：`project.yml` 中其 `type` 为 `extensionkit-extension`（Xcode 15+ 模板）。若使用更老 Xcode，改为 `app.extension` 后重新生成。
- **滚动截图录屏按钮找不到扩展**：确认真机运行（模拟器不支持系统录屏广播选择器），且 Bundle ID 与 `ScrollCaptureView.swift` 中一致。
- **App Group 读写失败**：检查所有 Target 的 App Group 勾选一致且前缀与代码一致。
