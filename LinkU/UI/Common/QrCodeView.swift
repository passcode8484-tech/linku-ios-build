import SwiftUI

/// 展示一个内容的二维码——"我的二维码"、群邀请码等复用这个。
struct QrCodeView: View {
    let content: String
    var size: CGFloat = 220

    var body: some View {
        Group {
            if let image = QrCodeUtils.generateImage(content: content) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(Text("二维码生成失败").font(.footnote))
            }
        }
        .frame(width: size, height: size)
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    QrCodeView(content: "linku://add?uid=demo")
}
