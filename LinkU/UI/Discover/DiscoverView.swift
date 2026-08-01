import SwiftUI

/// 对应 android-native ui/discover/DiscoverScreen.kt——朋友圈+圈子合并在一个 Tab 里，
/// 顶部切换。
struct DiscoverView: View {
    let container: AppContainer

    @State private var section: Section = .moments

    private enum Section: String, CaseIterable {
        case moments = "朋友圈"
        case circles = "圈子"
    }

    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .moments: MomentsFeedView(container: container)
                case .circles: CirclePlazaView(container: container)
                }
            }
            .navigationTitle(section.rawValue)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $section) {
                        ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
        }
    }
}
