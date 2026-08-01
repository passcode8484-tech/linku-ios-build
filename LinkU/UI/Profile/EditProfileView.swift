import PhotosUI
import SwiftUI

/// 对应 android-native ui/profile/EditProfileScreen 的精简版：头像/昵称/Link ID + 手机/邮箱换绑入口。
struct EditProfileView: View {
    let container: AppContainer

    @ObservedObject private var sessionStore: SessionStore
    @State private var nickname = ""
    @State private var linkId = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var uploadingAvatar = false
    @State private var savingNickname = false
    @State private var savingLinkId = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    init(container: AppContainer) {
        self.container = container
        self.sessionStore = container.sessionStore
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        ZStack {
                            Circle()
                                .fill(LinkuAvatarColors.forName(sessionStore.user?.nickname ?? ""))
                                .frame(width: 88, height: 88)
                                .overlay(
                                    Text(String((sessionStore.user?.nickname ?? "?").prefix(1)))
                                        .font(.title)
                                        .foregroundStyle(.white)
                                )
                            if uploadingAvatar {
                                Circle().fill(.black.opacity(0.4)).frame(width: 88, height: 88)
                                ProgressView().tint(.white)
                            }
                        }
                    }
                    .disabled(uploadingAvatar)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("昵称") {
                HStack {
                    TextField("昵称", text: $nickname)
                    if savingNickname { ProgressView() }
                }
                Button("保存昵称") { Task { await saveNickname() } }
                    .disabled(savingNickname || nickname.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section {
                HStack {
                    TextField("Link ID", text: $linkId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if savingLinkId { ProgressView() }
                }
                Button("保存 Link ID") { Task { await saveLinkId() } }
                    .disabled(savingLinkId || linkId.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Link ID")
            } footer: {
                Text("Link ID 是好友添加你时可以搜索到的唯一标识。")
            }

            Section {
                NavigationLink {
                    ChangeContactView(container: container, kind: .phone)
                } label: {
                    HStack {
                        Text("手机号")
                        Spacer()
                        Text(sessionStore.user?.phone ?? "未绑定").foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    ChangeContactView(container: container, kind: .email)
                } label: {
                    HStack {
                        Text("邮箱")
                        Spacer()
                        Text(sessionStore.user?.email ?? "未绑定").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("编辑资料")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nickname = sessionStore.user?.nickname ?? ""
            linkId = sessionStore.user?.linkId ?? ""
        }
        .onChange(of: avatarItem) { _, newItem in
            Task { await uploadAvatar(newItem) }
        }
        .alert("出错了", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func saveNickname() async {
        savingNickname = true
        do {
            try await container.userProfileRepository.setNickname(nickname.trimmingCharacters(in: .whitespaces))
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "更新失败"
        }
        savingNickname = false
    }

    private func saveLinkId() async {
        savingLinkId = true
        do {
            try await container.userProfileRepository.setLinkId(linkId.trimmingCharacters(in: .whitespaces))
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "更新失败"
        }
        savingLinkId = false
    }

    private func uploadAvatar(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        uploadingAvatar = true
        defer { uploadingAvatar = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "读取图片失败"
                return
            }
            try await container.userProfileRepository.uploadAvatar(fileData: data, fileName: "avatar.jpg", mimeType: "image/jpeg")
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "头像上传失败"
        }
    }
}
