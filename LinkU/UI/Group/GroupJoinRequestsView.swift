import SwiftUI

/// 群主/管理员审批入群申请——只在加群方式是"需要审批"时才有意义（GroupInfoView 已经按
/// joinPolicy 过滤了入口）。
struct GroupJoinRequestsView: View {
    let container: AppContainer
    let conversationId: Int64

    @Environment(\.dismiss) private var dismiss
    @State private var requests: [GroupJoinRequestView] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if requests.isEmpty {
                ContentUnavailableView("暂无待审批的申请", systemImage: "person.badge.clock")
            } else {
                List {
                    ForEach(requests) { request in
                        row(for: request)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("入群申请")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("出错了", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(for request: GroupJoinRequestView) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LinkuAvatarColors.forName(request.nickname ?? "用户\(request.userId)"))
                .frame(width: 40, height: 40)
                .overlay(Text(String((request.nickname ?? "?").prefix(1))).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(request.nickname ?? "用户\(request.userId)")
                if let message = request.message, !message.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await respond(request, approve: false) }
            } label: {
                Image(systemName: "xmark.circle").foregroundStyle(LinkuBrand.danger)
            }
            .buttonStyle(.plain)
            Button {
                Task { await respond(request, approve: true) }
            } label: {
                Image(systemName: "checkmark.circle").foregroundStyle(LinkuBrand.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        loading = true
        do {
            requests = try await container.chatRepository.groupJoinRequests(conversationId: conversationId)
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "加载失败"
        }
        loading = false
    }

    private func respond(_ request: GroupJoinRequestView, approve: Bool) async {
        do {
            if approve {
                try await container.chatRepository.approveGroupJoinRequest(conversationId: conversationId, requestId: request.id)
            } else {
                try await container.chatRepository.rejectGroupJoinRequest(conversationId: conversationId, requestId: request.id)
            }
            requests.removeAll { $0.id == request.id }
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "操作失败"
        }
    }
}
