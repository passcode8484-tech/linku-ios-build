import SwiftUI

/// 对应 android-native ui/contacts/AddFriendScreen/VM：按 publicUid/linkId 搜索 + 发送好友请求，
/// 也是"扫一扫加好友"扫描结果的落地页。
struct AddFriendView: View {
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var results: [UserSearchView] = []
    @State private var searching = false
    @State private var sendingTo: String?
    @State private var error: String?
    @State private var toast: String?
    @State private var showScanner = false
    @State private var joinGroupToken: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("LinkID / 手机号 / 邮箱", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await search() } }
                Button("搜索") { Task { await search() } }
                    .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }
            .padding()

            Button {
                showScanner = true
            } label: {
                Label("扫一扫加好友", systemImage: "qrcode.viewfinder")
            }
            .padding(.bottom, 8)

            if let error {
                Text(error).font(.footnote).foregroundStyle(LinkuBrand.danger)
            }
            if let toast {
                Text(toast).font(.footnote).foregroundStyle(.secondary)
            }

            List(results) { user in
                HStack(spacing: 12) {
                    Circle()
                        .fill(LinkuAvatarColors.forName(user.nickname))
                        .frame(width: 40, height: 40)
                        .overlay(Text(String(user.nickname.prefix(1))).foregroundStyle(.white))
                    VStack(alignment: .leading) {
                        Text(user.nickname)
                        Text(user.linkId.map { "@\($0)" } ?? user.publicUid)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(sendingTo == user.publicUid ? "已发送" : "加为好友") {
                        Task { await sendRequest(to: user.publicUid) }
                    }
                    .disabled(sendingTo == user.publicUid)
                    .buttonStyle(.borderedProminent)
                    .tint(LinkuBrand.primary)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("添加好友")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            NavigationStack {
                QrScannerView(title: "扫描二维码") { raw in
                    if let target = QrCodeUtils.parseProfilePayload(raw) {
                        keyword = target.searchKeyword
                        Task { await search() }
                    } else if let token = QrCodeUtils.parseGroupInviteToken(raw) {
                        joinGroupToken = token
                    } else {
                        error = "无法识别的二维码"
                    }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { joinGroupToken != nil },
            set: { if !$0 { joinGroupToken = nil } }
        )) {
            if let token = joinGroupToken {
                NavigationStack {
                    JoinGroupPreviewView(container: container, token: token)
                }
            }
        }
    }

    private func search() async {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searching = true
        error = nil
        toast = nil
        do {
            results = try await container.friendRepository.searchUsers(keyword: trimmed)
            if results.isEmpty { toast = "未找到相关用户" }
        } catch let ex as ApiException {
            error = ex.apiMessage
        } catch {
            error = "网络异常，请稍后重试"
        }
        searching = false
    }

    private func sendRequest(to publicUid: String) async {
        error = nil
        do {
            try await container.friendRepository.sendRequest(toPublicUid: publicUid)
            sendingTo = publicUid
        } catch let ex as ApiException {
            error = ex.apiMessage
        } catch {
            error = "网络异常，请稍后重试"
        }
    }
}
