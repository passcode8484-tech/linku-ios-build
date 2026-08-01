import SwiftUI

@main
struct LinkUApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .environmentObject(container)
        }
        .modelContainer(container.modelContainer)
    }
}
