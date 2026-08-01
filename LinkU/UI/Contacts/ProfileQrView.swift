import SwiftUI

/// 对应 android-native ui/profile/ProfileQrScreen.kt——"我的二维码"，好友拿手机扫这个加我。
struct ProfileQrView: View {
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sessionStore: SessionStore
    @State private var copied = false
    @State private var showShare = false

    init(container: AppContainer) {
        self.container = container
        self.sessionStore = container.sessionStore
    }

    var body: some View {
        VStack(spacing: 20) {
            if let user = sessionStore.user {
                Circle()
                    .fill(LinkuAvatarColors.forName(user.nickname))
                    .frame(width: 64, height: 64)
                    .overlay(Text(String(user.nickname.prefix(1))).font(.title2).foregroundStyle(.white))

                Text(user.nickname).font(.headline)

                QrCodeView(content: QrCodeUtils.buildProfilePayload(publicUid: user.publicUid, linkId: user.linkId))

                let idText = user.linkId.map { "@\($0)" } ?? user.publicUid
                Button {
                    UIPasteboard.general.string = idText
                    copied = true
                } label: {
                    Label(idText, systemImage: "doc.on.doc")
                }
                .font(.footnote)

                if copied {
                    Text("已复制").font(.caption2).foregroundStyle(.secondary)
                }

                Text("扫一扫上面的二维码，加我为 LinkU 好友")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                // 邀请归因/邀请码统计（android AttributionRepository 那一套）这次没做——见
                // AuthRepository.register 里已经留的 TODO(attribution)。这里只做最基础的
                // "分享我的 ID 文本"，够朋友手动加好友用，不追踪谁邀请了谁。
                Button {
                    showShare = true
                } label: {
                    Label("分享给好友", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            } else {
                ProgressView()
            }
        }
        .padding()
        .navigationTitle("我的二维码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
        .sheet(isPresented: $showShare) {
            if let user = sessionStore.user {
                let idText = user.linkId.map { "@\($0)" } ?? user.publicUid
                ActivityView(items: ["在 LinkU 上添加我为好友：\(idText)"])
            }
        }
    }
}
