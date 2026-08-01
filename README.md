# LinkU iOS（原生 Swift/SwiftUI）

对标 `android-native` 的功能范围，从零开发的原生 iOS 客户端。**本目录下的代码是在没有 Xcode/macOS
的环境里写的，从未被真正编译过** —— 请在 Mac 上按下面步骤生成工程、编译，把报错反馈回来再修。

## 首次构建

1. 安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）和
   [CocoaPods](https://cocoapods.org/)（`sudo gem install cocoapods`，或 `brew install cocoapods`）——
   `.xcodeproj`/`.xcworkspace`/`Pods/` 都不提交进仓库（见 `.gitignore`）。
2. E2EE 用的 `LibSignalClient`（signalapp/libsignal 官方 Swift 绑定）**官方明确不支持纯 SwiftPM
   依赖**（见其 `swift/README.md` "Use as a Swift Package" 一节："...is not supported"），canonical
   集成方式是 CocoaPods，所以流程是 XcodeGen 生成工程 + CocoaPods 织入这个包，不是单纯 SwiftPM。
   `pod install` 阶段会去下载预编译的 Rust 静态库，需要先设置校验用的环境变量（当前锁定的版本是
   v0.99.0，checksum 从对应 tag 的 GitHub Release 里 `libsignal-client-ios-build-v0.99.0.tar.gz.sha256`
   这个文件拿，已经帮你查好写在下面 —— 升级版本时要重新去对应 release 页面取新的 checksum）：
   ```bash
   export LIBSIGNAL_FFI_PREBUILD_CHECKSUM=66fbb653c520bbac20165f4d94d3a7af039407b451db44bb7943a4637dcee52c
   ```
3. 推送用的是 Firebase Cloud Messaging，不是裸 APNs（原因见下面"关键差异"一节）——需要你去
   [Firebase 控制台](https://console.firebase.google.com/)（用安卓端 LinkU 已经在用的那个 Firebase
   项目，不要新建一个）加一个 iOS App（Bundle ID 填 `com.linku.ios`），下载
   `GoogleService-Info.plist`，放到 `ios-native/LinkU/GoogleService-Info.plist`（这个文件已经在
   `.gitignore` 里，不会被提交）。还要在 Firebase 控制台"项目设置 → Cloud Messaging"上传一个
   APNs 认证密钥（.p8，从 Apple Developer 账号后台生成）——没有这一步 Firebase 拿不到 APNs 通道，
   推送会一直静默失败但不影响其他功能。这一步只有你能做，我这边没有 Firebase/Apple Developer
   账号的访问权限。
4. 在 `ios-native/` 目录下执行（顺序不能反，`pod install` 需要先有 `xcodegen generate` 生成的
   `.xcodeproj`）：
   ```bash
   xcodegen generate
   pod install
   open LinkU.xcworkspace
   ```
5. 用 Xcode 15+、iOS 17+ 模拟器或真机运行 `LinkU` scheme。**注意打开的是 `.xcworkspace`，不是
   `.xcodeproj`**——直接开 `.xcodeproj` 会因为找不到 Pods 里的 `LibSignalClient`/`FirebaseMessaging`
   而编译失败。推送要用真机测（模拟器收不到远程推送，Xcode 15+ 的模拟器可以用本地测试推送文件
   模拟，但真实 FCM 链路还是要真机）。

改了 `project.yml`（加 target/依赖/权限描述）之后要重新跑 `xcodegen generate` 再 `pod install`
（先 xcodegen 再 pod install，顺序同上）。改了 `Podfile` 只需要重新 `pod install`。

## 目录结构

```
ios-native/
  project.yml          # XcodeGen 工程定义，唯一的"工程文件"来源
  LinkU/
    App/                # App 入口、AppConfig、AppContainer（手动 DI 容器）
    Theme/               # 配色（跟 android-native ui/theme 逐字段对应，微信风格）
    Networking/          # ApiClient/ApiResponse（对应 Retrofit+OkHttp 那一层）
      Endpoints/           # 按 android-native 的 XxxApi.kt 一一对应
      WebSocket/           # ws/im 单连接多路复用客户端
    Storage/             # Keychain 封装、SessionStore
    Models/              # DTO（对应 remote/dto/*.kt）
    Data/                # Repository 层（对应 data/*Repository.kt）
    UI/                  # SwiftUI 视图 + ViewModel，按功能分包，对应 ui/*
```

## 与 android-native / windows-native 的关键差异

- **本地库**：SwiftData（对应 Room）。
- **安全存储**：Keychain（对应 EncryptedSharedPreferences / windows-native 的 DPAPI）。
- **E2EE**：用 `signalapp/libsignal` 官方 Swift 绑定，跟 windows-native 同源（不是 android 那个较老的
  `libsignal-android:0.70.0`），所以预期也需要 PreKeyBundle 里带 Kyber——服务端已经在 windows-native
  那轮加过对应的可选字段。
- **设备 id**：安卓 1:1 固定 `"1"`，windows-native 固定 `"2"`，iOS 计划固定 `"3"`——同一账号手机+电脑+
  iPhone 同时登录时不会互相顶掉 E2EE 身份。群聊 Sender Keys 三端统一用设备 id `1`。
- **推送**：不是裸 APNs，是 Firebase Cloud Messaging——查过服务端配置（`docs/PUSH_API.md`）发现
  `linku.push.provider` 只认 `log`/`fcm` 两个值，没有原生 APNs 通道；FCM 在 iOS 上的角色是"客户端
  集成 Firebase SDK 拿 FCM token，SDK 内部自动转发给 APNs"，服务端完全不用碰，跟安卓端发送逻辑
  完全一样，只是 `platform` 参数传 `ios`。不需要个推（个推是安卓在国内规避 GMS 缺失的方案，iOS 没
  有这个问题）。
- **通话**：LiveKit iOS SDK + CallKit（CallKit 是 iOS 系统级来电 UI 规范，安卓端没有直接对应物）。
- **应用更新**：iOS 不能像安卓那样下载 APK 自更新，只能引导跳 App Store，对应 `ui/update/` 的那套
  逻辑到 iOS 上会大幅简化。

## 进度

里程碑规划与进度见项目根目录的开发记录（M0 工程骨架 → M10 收尾），当前处于 M0。
