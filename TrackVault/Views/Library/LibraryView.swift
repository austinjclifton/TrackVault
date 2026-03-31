import CoreData
import SwiftUI

enum LibraryAddResult {
    case trackAdded
    case playlistCreated
    case cancelled
}

struct LibraryView: View {

    // MARK: - Environment

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var toastCoordinator: ToastCoordinator

    // MARK: - Store

    @StateObject private var store: LibraryStore

    // MARK: - UI State

    @State private var showAddSheet = false
    @State private var showPlaylists = true
    @State private var searchText = ""

    @State private var trackPendingEdit: Track?

    // Lightweight wrapper to satisfy `.sheet(item:)` without changing the Core Data model
    private struct IdentifiedTrack: Identifiable, Equatable {
        let id: String
        let objectID: NSManagedObjectID

        init(_ track: Track) {
            self.objectID = track.objectID
            self.id = track.objectID.uriRepresentation().absoluteString
        }
    }

    // Bridge optional Track? to an Identifiable wrapper for `.sheet(item:)`
    private var trackPendingEditIdentified: Binding<IdentifiedTrack?> {
        Binding<IdentifiedTrack?>(
            get: {
                guard let t = trackPendingEdit else { return nil }
                return IdentifiedTrack(t)
            },
            set: { newValue in
                if let newValue {
                    // Resolve back to a live Track in the current context
                    trackPendingEdit = (try? context.existingObject(with: newValue.objectID)) as? Track
                } else {
                    trackPendingEdit = nil
                }
            }
        )
    }

    @State private var activeFilter: LibraryStore.TrackFilter = .title
    @State private var selectedPlaylist: Playlist?

    // MARK: - Core Data

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)],
        animation: .default
    )
    private var tracks: FetchedResults<Track>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "lastPlayedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ],
        animation: .default
    )
    private var playlists: FetchedResults<Playlist>

    // MARK: - Init

    init(store: LibraryStore) {
        _store = StateObject(wrappedValue: store)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {

                LibraryPlaylistsSection(
                    playlists: Array(playlists),
                    showPlaylists: $showPlaylists,
                    onSelect: { selectedPlaylist = $0 }
                )

                Divider()
                    .padding(.horizontal, 8)

                LibrarySearchBar(
                    searchText: $searchText,
                    activeFilter: $activeFilter
                )

                tracksSection
            }
            .navigationTitle("TRACKVAULT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }

            .navigationDestination(item: $selectedPlaylist) { playlist in
                PlaylistDetailView(playlist: playlist)
            }

            .sheet(isPresented: $showAddSheet) {
                LibraryAddView(store: store, onFinish: handleAddResult)
                    .environment(\.managedObjectContext, context)
                    .environmentObject(container)
                    .environmentObject(toastCoordinator)
            }

            .sheet(item: trackPendingEditIdentified) { identified in
                // Resolve the Track from the current context when presenting
                if let resolved = try? context.existingObject(with: identified.objectID) as? Track {
                    TrackEditorView(
                        mode: .existing(resolved),
                        onFinish: {
                            showLibraryToast("Track updated", tone: .success)
                        }
                    )
                    .environment(\.managedObjectContext, context)
                } else {
                    // Fallback empty view if the object can't be resolved
                    EmptyView()
                }
            }

            .onAppear {
                store.updateContextIfNeeded(context)
            }
            .onChange(of: context) { _, newContext in
                store.updateContextIfNeeded(newContext)
            }
        }
        // Shared toast host for the library screen.
        // This screen now renders only library-inline toasts from the coordinator.
        .safeAreaInset(edge: .top) {
            libraryToastHost
        }
        .overlay(alignment: .bottom) {
            NowPlayingContainerView()
        }
        .onChange(of: player.lastError) { _, newValue in
            guard let msg = newValue else { return }
            showLibraryToast(msg, tone: .error)
        }
    }
}

// MARK: - Subviews

private extension LibraryView {

    var tracksSection: some View {
        Group {
            if tracks.isEmpty {
                emptyLibraryState
            } else if filteredTracks.isEmpty {
                emptySearchState
            } else {
                tracksList
            }
        }
    }

    var tracksList: some View {
        List {
            ForEach(trackSectionKeys, id: \.self) { letter in
                let sectionTracks = groupedFilteredTracks[letter] ?? []

                trackSectionHeader(letter)
                    .listRowInsets(
                        EdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16)
                    )
                    .listRowSeparator(.hidden)

                ForEach(Array(sectionTracks.enumerated()), id: \.element.objectID) { index, track in
                    LibraryTrackRow(track: track)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            play(track)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            deleteAction(track)
                            editAction(track)
                        }
                        .listRowInsets(
                            EdgeInsets(
                                top: index == 0 ? 0 : 6,
                                leading: 16,
                                bottom: index == sectionTracks.count - 1 ? 0 : 6,
                                trailing: 16
                            )
                        )
                        .listRowSeparator(index == sectionTracks.count - 1 ? .hidden : .visible)
                }
            }

            Color.clear
                .frame(height: 60)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .accessibilityLabel("Tracks")
    }

    func trackSectionHeader(_ letter: String) -> some View {
        HStack(spacing: 8) {
            Text(letter)
                .font(.subheadline.weight(.semibold))
                .fixedSize()

            Rectangle()
                .fill(.separator)
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var emptyLibraryState: some View {
        ContentUnavailableView {
            Label("No Tracks", systemImage: "music.note")
        } description: {
            Text("Tap + to add your first track.")
        } actions: {
            Button("Add Track") {
                showAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptySearchState: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("Try a different search or filter.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Toast Host

    var libraryToastHost: some View {
        VStack {
            Spacer()

            ToastRegionHost(
                style: .libraryInline,
                topPadding: 0,
                horizontalPadding: 16
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }
}

// MARK: - Toolbar

private extension LibraryView {

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 14) {

                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")

                Button {
                    container.toggleAppearance()
                } label: {
                    Image(systemName: container.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .foregroundStyle(container.isDarkMode ? .yellow : .primary)
                }
                .accessibilityLabel(
                    container.isDarkMode
                    ? "Switch to light mode"
                    : "Switch to dark mode"
                )
            }
        }
    }
}

// MARK: - Add Result Handling

private extension LibraryView {

    func handleAddResult(_ result: LibraryAddResult) {
        switch result {
        case .trackAdded:
            showLibraryToast("Track added", tone: .success)

        case .playlistCreated:
            showLibraryToast("Playlist created", tone: .success)

        case .cancelled:
            break
        }
    }
}

// MARK: - Track Actions

private extension LibraryView {

    func deleteAction(_ track: Track) -> some View {
        Button(role: .destructive) {
            if player.nowPlayingTrackID == track.objectID {
                player.clearQueue()
            }

            do {
                try container.trackDeletionService.deleteTrack(track)
                showLibraryToast("Track deleted", tone: .success)
            } catch {
                if let err = error as? LocalizedError,
                   let msg = err.errorDescription {
                    showLibraryToast(msg, tone: .error)
                } else {
                    showLibraryToast("Delete failed", tone: .error)
                }
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    func editAction(_ track: Track) -> some View {
        Button {
            trackPendingEdit = track
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.blue)
    }
}

// MARK: - Filtering

private extension LibraryView {

    var filteredTracks: [Track] {
        store.filteredTracks(
            from: Array(tracks),
            query: searchText,
            filter: activeFilter
        )
    }

    var groupedFilteredTracks: [String: [Track]] {
        Dictionary(grouping: filteredTracks) { track in
            sectionLetter(for: track, filter: activeFilter)
        }
    }

    var trackSectionKeys: [String] {
        groupedFilteredTracks.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs < rhs
        }
    }

    func sectionLetter(for track: Track, filter: LibraryStore.TrackFilter) -> String {
        let source: String

        switch filter {
        case .title:
            source = track.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        case .artist:
            source = track.displayArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let first = source.first else { return "#" }

        let letter = String(first).uppercased()
        return letter.range(of: "[A-Z]", options: .regularExpression) != nil ? letter : "#"
    }
}

// MARK: - Playback

private extension LibraryView {

    func play(_ track: Track) {
        guard let index = filteredTracks.firstIndex(where: { $0.objectID == track.objectID }) else {
            return
        }

        player.startQueue(filteredTracks, startAt: index)
    }
}

// MARK: - Toast Emission

private extension LibraryView {

    /// Emits a library-scoped toast through the shared coordinator.
    ///
    /// LibraryView no longer owns local toast state, timers, or overlay logic.
    /// It only emits toast events for user actions that change library state.
    func showLibraryToast(_ message: String, tone: ToastTone) {
        switch tone {
        case .success:
            toastCoordinator.showSuccess(
                message,
                style: .libraryInline
            )

        case .info:
            toastCoordinator.showInfo(
                message,
                style: .libraryInline
            )

        case .error:
            toastCoordinator.showError(
                message,
                style: .libraryInline
            )
        }
    }
}
