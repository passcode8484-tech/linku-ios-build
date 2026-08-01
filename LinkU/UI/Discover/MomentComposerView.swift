import PhotosUI
import SwiftUI

/// 对应 android-native ui/discover/MomentComposerViewModel。语音/视频/位置这些留到之后，
/// 先做"文字 + 最多 9 张图"这个最常用的路径。
struct MomentComposerView: View {
    let container: AppContainer
    var onPublished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [Data] = []
    @State private var publishing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $content)
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                .padding(.horizontal)

            if !selectedImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { _, data in
                            if let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            PhotosPicker(selection: $photoItems, maxSelectionCount: 9, matching: .images) {
                Label("添加图片", systemImage: "photo.on.rectangle")
            }
            .padding(.horizontal)

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(LinkuBrand.danger).padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top)
        .navigationTitle("发朋友圈")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if publishing {
                    ProgressView()
                } else {
                    Button("发表") { Task { await publish() } }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImages.isEmpty)
                }
            }
        }
        .onChange(of: photoItems) { _, items in
            Task {
                var datas: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
                }
                selectedImages = datas
            }
        }
    }

    private func publish() async {
        publishing = true
        errorMessage = nil
        do {
            var mediaItems: [MomentMediaItem] = []
            for (index, data) in selectedImages.enumerated() {
                let uploaded = try await container.momentRepository.uploadMedia(
                    fileData: data, fileName: "moment_\(index).jpg", mimeType: "image/jpeg", kind: "moment_image"
                )
                mediaItems.append(MomentMediaItem(isVideo: false, key: uploaded.objectKey))
            }
            _ = try await container.momentRepository.publish(content: content, mediaItems: mediaItems)
            onPublished()
            dismiss()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "发表失败，请重试"
        }
        publishing = false
    }
}
