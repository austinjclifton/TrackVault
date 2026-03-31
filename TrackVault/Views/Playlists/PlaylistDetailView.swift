//
//  PlaylistDetailView.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  PlaylistDetailView.swift
//  IceBox
//

import CoreData
import SwiftUI

struct PlaylistDetailView: View {

    // MARK: - Dependencies

    @ObservedObject var playlist: Playlist

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var toastCoordinator: ToastCoordinator

    private var repo: PlaylistRepository {
        PlaylistRepository(context: context)
    }

    // MARK: - UI State

    @State private var showAddTracksSheet = false
    @State private var preAddCount = 0
    @State private var showActionsConfirm = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            playlistToastHost
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showAddTracksSheet, onDismiss: handleAddTracksDismiss) {
            AddTracksToPlaylistView(playlist: playlist)
                .environment(\.managedObjectContext, context)
                .environmentObject(toastCoordinator)
        }
        .confirmationDialog(
            "Playlist Actions",
            isPresented: $showActionsConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive) {
                deletePlaylist()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

// MARK: - Layout

private extension PlaylistDetailView {

    var content: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            if playlist.itemsArray.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tracksList
            }
        }
    }
}

// MARK: - Header

private extension PlaylistDetailView {

    var headerRow: some View {
        HStack(spacing: 16) {
            playlistArtwork

            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(.title3)
                    .bold()
                    .lineLimit(1)

                Text(songCountText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    var songCountText: String {
        let count = playlist.itemsArray.count
        return "\(count) song\(count == 1 ? "" : "s")"
    }

    var playlistArtwork: some View {
        Group {
            if let data = playlist.artworkData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Content

private extension PlaylistDetailView {

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("This playlist is empty")
                .font(.headline)

            Text("Add songs from your library using the + button.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 40)
    }

    var tracksList: some View {
        List {
            ForEach(Array(playlist.itemsArray.enumerated()), id: \.element.objectID) { index, item in
                Button {
                    play(item)
                } label: {
                    PlaylistTrackRow(
                        track: item.track,
                        showsSelection: false,
                        isSelected: false
                    )
                }
                .buttonStyle(.plain)
                .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                .listRowSeparator(
                    index == playlist.itemsArray.count - 1 ? .hidden : .visible,
                    edges: .bottom
                )
            }
            .onDelete(perform: removeTracks)
        }
        .listStyle(.plain)
        .accessibilityLabel("Playlist tracks")
    }
}

// MARK: - Toast Host

private extension PlaylistDetailView {

    @ViewBuilder
    var playlistToastHost: some View {
        if isShowingPlaylistToast {
            HStack {
                Spacer(minLength: 0)

                ToastRegionHost(
                    style: .playlistInline,
                    topPadding: 0,
                    horizontalPadding: 16
                )
                .allowsHitTesting(false)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 48)
        }
    }

    var isShowingPlaylistToast: Bool {
        toastCoordinator.currentToast?.style == .playlistInline
    }
}

// MARK: - Toolbar

private extension PlaylistDetailView {

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                togglePin()
            } label: {
                Image(systemName: playlist.isPinned ? "pin.slash" : "pin")
            }
            .accessibilityLabel(playlist.isPinned ? "Unpin playlist" : "Pin playlist")

            NavigationLink {
                PlaylistEditView(playlist: playlist) { result in
                    handleEditResult(result)
                }
                .environmentObject(toastCoordinator)
            } label: {
                Image(systemName: "pencil")
            }
            .accessibilityLabel("Edit playlist")

            Button {
                preAddCount = playlist.itemsArray.count
                showAddTracksSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add songs")

            Button(role: .destructive) {
                showActionsConfirm = true
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete playlist")
        }
    }
}

// MARK: - Actions

private extension PlaylistDetailView {

    func togglePin() {
        do {
            try repo.togglePin(playlist)
            showPlaylistToast(
                playlist.isPinned ? "Playlist pinned" : "Playlist unpinned",
                tone: .info
            )
        } catch {
            showPlaylistToast(error.localizedDescription, tone: .error)
        }
    }

    func deletePlaylist() {
        do {
            try repo.deletePlaylist(playlist)
            dismiss()
        } catch {
            showPlaylistToast(error.localizedDescription, tone: .error)
        }
    }

    func play(_ item: PlaylistTrack) {
        let tracks = playlist.tracksArray

        guard let index = tracks.firstIndex(where: { $0.objectID == item.track.objectID }) else {
            return
        }

        playlist.lastPlayedAt = Date()
        playlist.updatedAt = Date()
        try? context.save()

        player.startQueue(tracks, startAt: index)
    }

    func removeTracks(at offsets: IndexSet) {
        let items = playlist.itemsArray
        let tracks = offsets.map { items[$0].track }

        do {
            for track in tracks {
                try repo.removeTrack(track, from: playlist)
            }

            showPlaylistToast(
                tracks.count == 1 ? "Removed song" : "Removed \(tracks.count) songs",
                tone: .error
            )
        } catch {
            showPlaylistToast(error.localizedDescription, tone: .error)
        }
    }

    func handleAddTracksDismiss() {
        let after = playlist.itemsArray.count
        let added = max(0, after - preAddCount)

        guard added > 0 else { return }

        showPlaylistToast(
            "Added \(added) song\(added == 1 ? "" : "s")",
            tone: .success
        )
    }

    func handleEditResult(_ result: PlaylistEditView.Result) {
        switch result {
        case .saved:
            showPlaylistToast("Playlist updated", tone: .info)

        case .failed(let message):
            showPlaylistToast(message, tone: .error)
        }
    }
}

// MARK: - Toast Emission

private extension PlaylistDetailView {

    func showPlaylistToast(_ message: String, tone: ToastTone) {
        switch tone {
        case .success:
            toastCoordinator.showSuccess(message, style: .playlistInline)

        case .info:
            toastCoordinator.showInfo(message, style: .playlistInline)

        case .error:
            toastCoordinator.showError(message, style: .playlistInline)
        }
    }
}
