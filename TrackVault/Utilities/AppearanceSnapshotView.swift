import SwiftUI
import UIKit

struct AppearanceSnapshotView<Content: View>: View {

    @Binding var snapshotImage: UIImage?
    let content: Content

    init(
        snapshotImage: Binding<UIImage?>,
        @ViewBuilder content: () -> Content
    ) {
        self._snapshotImage = snapshotImage
        self.content = content()
    }

    var body: some View {
        ZStack {
            content

            if let image = snapshotImage {
                Image(uiImage: image)
                    .resizable()
                    .ignoresSafeArea()
                    .opacity(snapshotImage == nil ? 0 : 1)
                    .animation(.easeInOut(duration: 0.24), value: snapshotImage)
                    .zIndex(1000)
            }
        }
    }
}
