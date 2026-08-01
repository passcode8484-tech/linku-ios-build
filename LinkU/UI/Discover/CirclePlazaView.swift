import SwiftUI

/// 对应 android-native ui/discover/CirclePlazaScreen.kt + CircleViewModel。
struct CirclePlazaView: View {
    let container: AppContainer

    @State private var scope: Scope = .plaza
    @State private var circles: [CircleView] = []
    @State private var errorMessage: String?
    @State private var showCreate = false

    private enum Scope: String, CaseIterable {
        case plaza = "广场"
        case mine = "我的"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            List(circles) { circle in
                NavigationLink {
                    CircleDetailView(container: container, circleId: circle.id)
                } label: {
                    row(for: circle)
                }
            }
            .listStyle(.plain)
            .overlay {
                if circles.isEmpty {
                    ContentUnavailableView("暂无圈子", systemImage: "person.3.sequence")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus.circle") }
            }
        }
        .task { await refresh() }
        .onChange(of: scope) { _, _ in Task { await refresh() } }
        .refreshable { await refresh() }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                CreateCircleView(container: container) { Task { await refresh() } }
            }
        }
        .alert("加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(for circle: CircleView) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LinkuAvatarColors.forName(circle.name))
                .frame(width: 44, height: 44)
                .overlay(Text(String(circle.name.prefix(1))).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(circle.name).font(.body)
                Text("\(circle.memberCount) 位成员").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if circle.joined {
                Text("已加入").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func refresh() async {
        do {
            circles = scope == .plaza ? try await container.circleRepository.plaza() : try await container.circleRepository.mine()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "网络异常，请稍后重试"
        }
    }
}

struct CreateCircleView: View {
    let container: AppContainer
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var creating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("圈子名称") {
                TextField("名称", text: $name)
            }
            Section("简介") {
                TextField("介绍一下这个圈子", text: $description)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(LinkuBrand.danger)
            }
        }
        .navigationTitle("创建圈子")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if creating {
                    ProgressView()
                } else {
                    Button("创建") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() async {
        creating = true
        do {
            _ = try await container.circleRepository.create(name: name, description: description.isEmpty ? nil : description)
            onCreated()
            dismiss()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "创建失败"
        }
        creating = false
    }
}
