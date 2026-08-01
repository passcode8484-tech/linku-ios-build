# LibSignalClient 官方明确表态"不支持作为纯 SwiftPM 依赖使用"（见
# https://github.com/signalapp/libsignal/blob/main/swift/README.md 的 "Use as a Swift Package"
# 一节），CocoaPods 才是它认为的 canonical 集成方式——所以这里没有在 project.yml 里加 SPM
# package，而是单独这份 Podfile。`xcodegen generate` 先生成 LinkU.xcodeproj，然后这份 Podfile
# 把 Pods 织进去、产出 LinkU.xcworkspace，后续要打开的是 .xcworkspace，不是 .xcodeproj。

platform :ios, '17.0'
use_frameworks!

target 'LinkU' do
  # 用固定 tag（跟 CHAT_E2EE.md/windows-native 用的同一条 signalapp/libsignal 主干），
  # 不用 branch，避免协议库无预警升级导致跟服务端/其他客户端的 wire format 悄悄对不上。
  pod 'LibSignalClient', git: 'https://github.com/signalapp/libsignal.git', tag: 'v0.99.0'

  # 推送用 Firebase Cloud Messaging，不是裸 APNs——服务端 linku.push.provider 只认 log/fcm
  # 两种（见 docs/PUSH_API.md），FCM 本身在 iOS 上就是"客户端集成 Firebase SDK 拿 FCM token，
  # 内部自动转发给 APNs"，服务端完全不用改一行代码就能像发安卓推送一样发 iOS 推送。
  # 需要在 Firebase 控制台给这个 iOS app 建一个条目、下载 GoogleService-Info.plist 放进
  # LinkU/ 目录（这一步只有你能做，我这边没有 Firebase 项目的访问权限），详见 README.md。
  pod 'FirebaseMessaging'
end
