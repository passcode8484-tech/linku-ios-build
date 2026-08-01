import SwiftUI

/// 对应 android-native ui/profile/PrivacyDetailScreen——谁能搜到我、谁能加我好友、已读回执。
/// 服务端没有"读取当前值"以外的东西需要额外拉取，进页面先 GET 一次当前设置，每个开关改动
/// 立刻单独 POST（不做"统一保存"按钮），跟 android 的即改即生效体验一致。
struct PrivacyView: View {
    let container: AppContainer

    @State private var privacy: UserPrivacyView?
    @State private var loading = true
    @State private var errorMessage: String?

    private let friendRequestOptions: [(value: String, label: String)] = [
        ("ALL", "任何人都可以添加"),
        ("SEARCH_ONLY", "仅通过搜索找到我的人"),
        ("NONE", "不接受任何好友请求"),
    ]

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if let privacy {
                Form {
                    Section("谁可以搜索到我") {
                        Toggle("通过 Link ID", isOn: Binding(
                            get: { privacy.allowSearchByLinkId },
                            set: { update(allowSearchByLinkId: $0) }
                        ))
                        Toggle("通过手机号", isOn: Binding(
                            get: { privacy.allowSearchByPhone },
                            set: { update(allowSearchByPhone: $0) }
                        ))
                        Toggle("通过邮箱", isOn: Binding(
                            get: { privacy.allowSearchByEmail },
                            set: { update(allowSearchByEmail: $0) }
                        ))
                    }

                    Section("谁可以添加我为好友") {
                        ForEach(friendRequestOptions, id: \.value) { option in
                            Button {
                                update(allowFriendRequestFrom: option.value)
                            } label: {
                                HStack {
                                    Text(option.label).foregroundStyle(.primary)
                                    Spacer()
                                    if privacy.allowFriendRequestFrom == option.value {
                                        Image(systemName: "checkmark").foregroundStyle(LinkuBrand.primary)
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        Toggle("发送已读回执", isOn: Binding(
                            get: { privacy.allowReadReceipt },
                            set: { update(allowReadReceipt: $0) }
                        ))
                    } header: {
                        Text("消息")
                    } footer: {
                        Text("关闭后，你也将无法看到对方的已读状态。")
                    }
                }
            } else if let errorMessage {
                ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle("隐私")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        do {
            privacy = try await container.userProfileRepository.fetchPrivacy()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "加载失败"
        }
        loading = false
    }

    private func update(
        allowSearchByLinkId: Bool? = nil,
        allowSearchByPhone: Bool? = nil,
        allowSearchByEmail: Bool? = nil,
        allowFriendRequestFrom: String? = nil,
        allowReadReceipt: Bool? = nil
    ) {
        Task {
            do {
                privacy = try await container.userProfileRepository.updatePrivacy(
                    allowSearchByLinkId: allowSearchByLinkId,
                    allowSearchByPhone: allowSearchByPhone,
                    allowSearchByEmail: allowSearchByEmail,
                    allowFriendRequestFrom: allowFriendRequestFrom,
                    allowReadReceipt: allowReadReceipt
                )
            } catch let ex as ApiException {
                errorMessage = ex.apiMessage
            } catch {
                errorMessage = "更新失败"
            }
        }
    }
}
