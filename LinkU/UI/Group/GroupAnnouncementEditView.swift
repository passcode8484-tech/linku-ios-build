import SwiftUI

/// 对应 android-native ui/profile/GroupAnnouncementScreen——群公告，群主/管理员可编辑，
/// 普通成员只读。命名带 Edit 后缀是为了跟 ChatModels.swift 里同名的 `GroupAnnouncementView`
/// DTO 区分开，不是两个东西重名。
struct GroupAnnouncementEditView: View {
    let container: AppContainer
    let conversationId: Int64
    let canEdit: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var announcement: GroupAnnouncementView?
    @State private var editing = false
    @State private var draft = ""
    @State private var loading = true
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if editing {
                Form {
                    Section {
                        TextEditor(text: $draft)
                            .frame(minHeight: 160)
                    }
                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(LinkuBrand.danger)
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let content = announcement?.content, !content.isEmpty {
                            Text(content)
                        } else {
                            Text("还没有群公告")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
        }
        .navigationTitle("群公告")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(editing ? "取消" : "关闭") {
                    if editing {
                        editing = false
                        errorMessage = nil
                    } else {
                        dismiss()
                    }
                }
            }
            if canEdit {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if editing {
                        Button {
                            Task { await save() }
                        } label: {
                            if saving { ProgressView() } else { Text("保存") }
                        }
                        .disabled(saving)
                    } else {
                        Button("编辑") {
                            draft = announcement?.content ?? ""
                            editing = true
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        do {
            announcement = try await container.chatRepository.groupAnnouncement(conversationId: conversationId)
        } catch {
            // 群还没设过公告时服务端可能直接 404/空数据——当成"暂无公告"处理，不当错误弹出来。
            announcement = nil
        }
        loading = false
    }

    private func save() async {
        saving = true
        errorMessage = nil
        do {
            announcement = try await container.chatRepository.updateGroupAnnouncement(
                conversationId: conversationId, content: draft.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            editing = false
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "保存失败"
        }
        saving = false
    }
}
