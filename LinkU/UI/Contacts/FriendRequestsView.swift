import SwiftData
import SwiftUI

/// 对应 android-native ui/contacts/FriendRequestsScreen/VM。
struct FriendRequestsView: View {
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FriendRequestEntity.id, order: .reverse) private var requests: [FriendRequestEntity]
    @State private var processingId: Int64?
    @State private var error: String?

    var body: some View {
        List(requests) { request in
            HStack(spacing: 12) {
                Circle()
                    .fill(LinkuAvatarColors.forName(request.fromNickname))
                    .frame(width: 40, height: 40)
                    .overlay(Text(String(request.fromNickname.prefix(1))).foregroundStyle(.white))
                VStack(alignment: .leading) {
                    Text(request.fromNickname)
                    if let message = request.message, !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                statusView(for: request)
            }
        }
        .overlay {
            if requests.isEmpty {
                ContentUnavailableView("暂无新的好友请求", systemImage: "person.crop.circle.badge.checkmark")
            }
        }
        .navigationTitle("新的朋友")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
        .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    @ViewBuilder
    private func statusView(for request: FriendRequestEntity) -> some View {
        switch request.status {
        case "PENDING":
            HStack(spacing: 8) {
                Button("拒绝") { Task { await handle(request, accept: false) } }
                    .buttonStyle(.bordered)
                Button("同意") { Task { await handle(request, accept: true) } }
                    .buttonStyle(.borderedProminent)
                    .tint(LinkuBrand.primary)
            }
            .disabled(processingId == request.id)
        case "ACCEPTED":
            Text("已同意").font(.caption).foregroundStyle(.secondary)
        case "REJECTED":
            Text("已拒绝").font(.caption).foregroundStyle(.secondary)
        default:
            Text(request.status).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func handle(_ request: FriendRequestEntity, accept: Bool) async {
        processingId = request.id
        do {
            if accept {
                try await container.friendRepository.acceptRequest(requestId: request.id)
            } else {
                try await container.friendRepository.rejectRequest(requestId: request.id)
            }
        } catch let ex as ApiException {
            error = ex.apiMessage
        } catch {
            self.error = "网络异常，请稍后重试"
        }
        processingId = nil
    }
}
