import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Notifications

extension Notification.Name {
    static let playlistDeleted = Notification.Name("playlistDeleted")
}

// MARK: - Mode

enum LibraryAddMode: String, CaseIterable, Hashable {
    case song = "Add Track"
    case playlist = "New Playlist"
}

// MARK: - View

struct LibraryAddView: View {

    // MARK: - Dependencies

    @ObservedObject var store: LibraryStore
    let onFinish: (LibraryAddResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var toastCoordinator: ToastCoordinator

    // MARK: - UI State

    @State private var mode: LibraryAddMode = .song

    @State private var showFileImporter = false
    @State private var photoVideoItem: PhotosPickerItem?

    @State private var isImporting = false
    @State private var progress: Double?
    @State private var errorMessage: String?

    @State private var draft: ImportedTrackDraft?
    @State private var showEditor = false

    @State private var playlistName = ""
    @State private var importTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                modePicker

                if mode == .song {
                    importSection
                } else {
                    playlistSection
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showEditor) {
            editorSheet
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .onChange(of: photoVideoItem) { _, newItem in
            guard let newItem else { return }
            handlePhotoVideoImport(newItem)
        }
        .alert(
            "Import Failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            importTask?.cancel()
            importTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistDeleted)) { notification in
            let name = (notification.userInfo?["name"] as? String) ?? "Playlist"
            toastCoordinator.showSuccess("\(name) deleted", style: .globalTop)
        }
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
        .safeAreaInset(edge: .top) {
            addFlowToastHost
        }
    }
}

// MARK: - Toolbar

private extension LibraryAddView {

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") {
                cancelAndDismiss()
            }
            .disabled(isImporting)
        }
    }

    func cancelAndDismiss() {
        importTask?.cancel()
        importTask = nil

        Task {
            await discardDraftIfNeeded()
            await MainActor.run {
                onFinish(.cancelled)
                dismiss()
            }
        }
    }
}

// MARK: - Mode Picker

private extension LibraryAddView {

    var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(LibraryAddMode.allCases, id: \.self) { mode in
                Text(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .disabled(isImporting)
    }
}

// MARK: - Editor Sheet

private extension LibraryAddView {

    @ViewBuilder
    var editorSheet: some View {
        if let draft {
            TrackEditorView(
                mode: .draft(draft),
                onFinish: {
                    showEditor = false
                    onFinish(.trackAdded)
                    dismiss()
                }
            )
            .environmentObject(toastCoordinator)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Song Import UI

private extension LibraryAddView {

    var importSection: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                PhotosPicker(
                    selection: $photoVideoItem,
                    matching: .videos
                ) {
                    ImportTile(
                        title: "Camera Roll",
                        subtitle: "Screen recordings",
                        systemImage: "video.fill",
                        backgroundColor: .blue
                    )
                }
                .disabled(isImporting)

                Button {
                    showFileImporter = true
                } label: {
                    ImportTile(
                        title: "Files",
                        subtitle: "Audio / Video",
                        systemImage: "folder.fill",
                        backgroundColor: .red
                    )
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
            }
            .opacity(isImporting ? 0.6 : 1)

            if isImporting || progress != nil {
                progressArea
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isImporting)
        .animation(.easeInOut(duration: 0.2), value: progress)
    }

    var progressArea: some View {
        VStack(spacing: 10) {
            Text("Extracting audio, this may take a minute")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let progress {
                ProgressView(value: progress)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Playlist UI

private extension LibraryAddView {

    var playlistSection: some View {
        VStack(spacing: 20) {
            TextField("New Playlist", text: $playlistName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .disabled(isImporting)

            Button {
                createPlaylist()
            } label: {
                Text("Create Playlist")
                    .font(.headline)
                    .foregroundStyle(createPlaylistButtonTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(createPlaylistButtonBackground)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(createPlaylistButtonBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canCreatePlaylist)
            .animation(.easeInOut(duration: 0.15), value: canCreatePlaylist)
        }
        .padding(.top, 8)
    }

    var normalizedPlaylistName: String {
        playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCreatePlaylist: Bool {
        !isImporting && !normalizedPlaylistName.isEmpty
    }

    var createPlaylistButtonBackground: some ShapeStyle {
        canCreatePlaylist ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.18))
    }

    var createPlaylistButtonBorder: Color {
        canCreatePlaylist ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.38)
    }

    var createPlaylistButtonTextColor: Color {
        canCreatePlaylist ? .white : .primary.opacity(0.72)
    }

    func createPlaylist() {
        let name = normalizedPlaylistName
        guard !name.isEmpty else { return }

        do {
            try store.createPlaylist(name: name)
            onFinish(.playlistCreated)
            dismiss()
        } catch {
            errorMessage = "unable to create playlist"
        }
    }
}

// MARK: - Import Logic

private extension LibraryAddView {

    func handleFileImport(_ result: Result<[URL], Error>) {
        guard !isImporting else { return }

        startImport {
            do {
                guard let url = try result.get().first else { return }

                let stagedDraft = try await container.importCoordinator.stageFromFiles(
                    sourceURL: url,
                    onProgress: makeProgressHandler()
                )

                await MainActor.run {
                    draft = stagedDraft
                    showEditor = true
                }
            } catch {
                await presentImportFailure(error)
            }
        }
    }

    func handlePhotoVideoImport(_ item: PhotosPickerItem) {
        guard !isImporting else { return }

        startImport {
            defer {
                Task { @MainActor in
                    photoVideoItem = nil
                }
            }

            do {
                let stagedDraft = try await container.importCoordinator.stageFromPhotosVideo(
                    item: item,
                    onProgress: makeProgressHandler()
                )

                await MainActor.run {
                    draft = stagedDraft
                    showEditor = true
                }
            } catch {
                await presentImportFailure(error)
            }
        }
    }

    func startImport(_ operation: @escaping @Sendable () async -> Void) {
        importTask?.cancel()

        importTask = Task {
            await MainActor.run {
                beginImport()
            }

            await discardDraftIfNeeded()
            await operation()

            if !Task.isCancelled {
                await MainActor.run {
                    endImport()
                }
            }
        }
    }

    @preconcurrency
    func makeProgressHandler() -> @Sendable (Double) -> Void {
        { value in
            Task { @MainActor in
                progress = min(max(value, 0), 1)
            }
        }
    }

    @MainActor
    func beginImport() {
        isImporting = true
        progress = nil
        errorMessage = nil
    }

    @MainActor
    func endImport() {
        isImporting = false
        progress = nil
    }

    func discardDraftIfNeeded() async {
        guard let draft else { return }
        await draft.discard()

        await MainActor.run {
            self.draft = nil
        }
    }

    func presentImportFailure(_ error: Error) async {
        await MainActor.run {
            endImport()
            errorMessage = mapImportError(error)
        }
    }
}

// MARK: - Toast Host

private extension LibraryAddView {

    var addFlowToastHost: some View {
        HStack {
            ToastRegionHost(
                style: .globalTop,
                topPadding: 8,
                horizontalPadding: 0
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Errors

private extension LibraryAddView {

    func mapImportError(_ error: Error) -> String {
        if let error = error as? LocalizedError,
           let description = error.errorDescription,
           !description.isEmpty {
            return description
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return "import failed"
        }

        return "import failed"
    }
}

