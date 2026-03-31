//
//  AddTracksToPlaylistView.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  AddTracksToPlaylistView.swift
//  IceBox
//

import SwiftUI
import CoreData

struct AddTracksToPlaylistView: View {

    // MARK: - Input

    let playlist: Playlist

    // MARK: - Environment

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var repo: PlaylistRepository {
        PlaylistRepository(context: context)
    }

    // MARK: - Data

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "title", ascending: true),
            NSSortDescriptor(key: "artist", ascending: true)
        ],
        animation: .default
    )
    private var allTracks: FetchedResults<Track>

    // MARK: - Selection State

    @State private var selectedIDs: Set<NSManagedObjectID> = []
    @State private var isSaving = false

    // MARK: - Derived Data

    /// Track IDs already present in the playlist
    private var existingTrackIDs: Set<NSManagedObjectID> {
        Set(
            playlist.itemsArray
                .map { $0.track.objectID }
        )
    }

    /// Tracks that can actually be added
    private var addableTracks: [Track] {
        allTracks.filter { !existingTrackIDs.contains($0.objectID) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                if addableTracks.isEmpty {
                    emptyStateRow
                } else {
                    ForEach(addableTracks, id: \.objectID) { track in
                        Button {
                            toggle(track)
                        } label: {
                            PlaylistTrackRow(
                                track: track,
                                showsSelection: true,
                                isSelected: selectedIDs.contains(track.objectID)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
    }
}

// MARK: - Toolbar

private extension AddTracksToPlaylistView {

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {

        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") {
                dismiss()
            }
            .disabled(isSaving)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button("Add") {
                addSelected()
            }
            .bold()
            .disabled(selectedIDs.isEmpty || isSaving)
        }
    }
}

// MARK: - Logic

private extension AddTracksToPlaylistView {

    func toggle(_ track: Track) {
        let id = track.objectID
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func addSelected() {
        guard !isSaving else { return }
        isSaving = true

        let tracks = addableTracks.filter {
            selectedIDs.contains($0.objectID)
        }

        do {
            _ = try repo.add(tracks: tracks, to: playlist)
            dismiss()
        } catch {
            // Fail silently; parent handles feedback
            isSaving = false
        }
    }
}

// MARK: - Empty State

private extension AddTracksToPlaylistView {

    var emptyStateRow: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("All songs already added")
                .font(.headline)

            Text("This playlist already contains every song in your library.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowSeparator(.hidden)
    }
}
