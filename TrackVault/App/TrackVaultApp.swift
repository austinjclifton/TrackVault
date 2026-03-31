import SwiftUI

@main
struct TrackVaultApp: App {

    @StateObject private var container = AppContainer()
    @StateObject private var toastCoordinator = ToastCoordinator()

    var body: some Scene {
        WindowGroup {
            AppearanceSnapshotView(
                snapshotImage: $container.appearanceSnapshot
            ) {
                LibraryView(store: container.libraryStore)
                    .environment(\.managedObjectContext, container.viewContext)
                    .environmentObject(container)
                    .environmentObject(container.audioPlayer)
                    .environmentObject(toastCoordinator)
                    .preferredColorScheme(container.preferredColorScheme)
                    .onAppear {
                        container.markAppearanceReady()
                    }
            }
        }
    }
}
