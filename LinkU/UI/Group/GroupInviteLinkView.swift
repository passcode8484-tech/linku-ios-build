import SwiftUI

/// 对应 android-native ui/group/GroupInfoScreen.kt 里的 GroupInviteScreen——生成群邀请二维码/链接。
/// 二维码内容直接是官网落地页 URL（`AppConfig.groupInviteWebURL`），不是 `linku://` scheme——
/// 跟 android 一致，这样微信扫码之类的场景也能打开落地页（app scheme 只有已装 App 的设备能识别）。
struct GroupInviteLinkView: View {
    let container: AppContainer
    let conversationId: Int64

    @Environment(\.dismiss) private var dismiss
    @State private var token: GroupInviteTokenView?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var showShare = false

    private var inviteURL: String? {
        guard let token else { return nil }
        let locale = Locale.current.language.languageCode?.identifier ?? "zh"
        return AppConfig.groupInviteWebURL(token: token.token, locale: locale)
    }

    var body: some View {
        VStack(spacing: 16) {
            if loading {
                ProgressView()
            } else if let inviteURL {
                QrCodeView(content: inviteURL, size: 220)
                Text("扫描二维码加入群聊")
                    .foregroundStyle(.secondary)
                Text("邀请链接有一定有效期，过期后需要重新生成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showShare = true
                } label: {
                    Label("分享邀请链接", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(LinkuBrand.primary)
            } else if let errorMessage {
                ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
            }
        }
        .padding()
        .navigationTitle("邀请链接")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showShare) {
            if let inviteURL {
                ActivityView(items: [inviteURL])
            }
        }
    }

    private func load() async {
        loading = true
        do {
            token = try await container.chatRepository.createGroupInviteToken(conversationId: conversationId)
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "生成邀请链接失败"
        }
        loading = false
    }
}
