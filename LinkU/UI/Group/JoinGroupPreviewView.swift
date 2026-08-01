import SwiftUI

/// 扫描/打开群邀请链接后的落地页——对应 android GroupInvitePreviewScreen 那一路。加群方式是
/// "自动通过"时直接进群，"需要审批"时提交申请，两种情况服务端用同一个接口
/// （`joinGroupByToken`），返回的文案已经说明白是哪种结果，这里直接展示，不用客户端自己猜。
struct JoinGroupPreviewView: View {
    let container: AppContainer
    let token: String

    @Environment(\.dismiss) private var dismiss
    @State private var preview: GroupInvitePreviewView?
    @State private var loading = true
    @State private var joining = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            if loading {
                ProgressView()
            } else if let preview {
                Circle()
                    .fill(LinkuAvatarColors.forName(preview.title))
                    .frame(width: 72, height: 72)
                    .overlay(Text(String(preview.title.prefix(1))).font(.title).foregroundStyle(.white))
                Text(preview.title).font(.title3.bold())
                Text("\(preview.memberCount) 位成员").foregroundStyle(.secondary)

                if let resultMessage {
                    Text(resultMessage)
                        .foregroundStyle(LinkuBrand.primary)
                        .multilineTextAlignment(.center)
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(LinkuBrand.primary)
                } else if preview.alreadyMember {
                    Text("你已经是本群成员").foregroundStyle(.secondary)
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(LinkuBrand.primary)
                } else {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(LinkuBrand.danger).font(.footnote)
                    }
                    Button {
                        Task { await join() }
                    } label: {
                        if joining {
                            ProgressView()
                        } else {
                            Text(preview.joinPolicy == "AUTO" ? "加入群聊" : "申请加入")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LinkuBrand.primary)
                    .disabled(joining)

                    if preview.joinPolicy != "AUTO" {
                        Text("该群需要群主/管理员审批后才能加入").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if let errorMessage {
                ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
            }
        }
        .padding()
        .navigationTitle("群邀请")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        do {
            preview = try await container.chatRepository.previewGroupInvite(token: token)
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "邀请链接无效或已过期"
        }
        loading = false
    }

    private func join() async {
        joining = true
        errorMessage = nil
        do {
            resultMessage = try await container.chatRepository.joinGroupByToken(token: token)
            try? await container.chatRepository.refreshConversations()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "加入失败"
        }
        joining = false
    }
}
