//
//  PlaylistsView.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  PlaylistsView.swift
//  IceBox
//

import CoreData
import SwiftUI

struct PlaylistsView: View {

    // MARK: - Environment

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var toastCoordinator: ToastCoordinator

    // MARK: - Repository

    private var repo: PlaylistRepository {
        PlaylistRepository(context: context)
    }

    // MARK: - Data (Pinned first, then last played, then newest)

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "lastPlayedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ],
        animation: .default
    )
    private var playlists: FetchedResults<Playlist>

    // MARK: - UI State

    @State private var showingCreate = false
    @State private var newName = ""
    @State private var didCreatePlaylist = false

    // MARK: - Layout

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 140), spacing: 16)
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(playlists, id: \.objectID) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            PlaylistTile(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showingCreate, onDismiss: handleCreateDismiss) {
                createPlaylistSheet
            }
        }
    }
}

// MARK: - Toolbar

private extension PlaylistsView {

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            playlistsNavCenterContent
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                newName = ""
                didCreatePlaylist = false
                showingCreate = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Create playlist")
        }
    }

    /// The center region of the navigation bar.
    ///
    /// When there is an active playlists toast, it renders inline in the same
    /// nav row as the plus button. Otherwise, it falls back to the screen title.
    @ViewBuilder
    var playlistsNavCenterContent: some View {
        if isShowingPlaylistsToast {
            ToastRegionHost(
                style: .globalTop,
                topPadding: 0,
                horizontalPadding: 0
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .allowsHitTesting(false)
        } else {
            Text("Playlists")
                .font(.headline)
                .lineLimit(1)
        }
    }

    var isShowingPlaylistsToast: Bool {
        toastCoordinator.currentToast?.style == .globalTop
    }
}

// MARK: - Create Playlist Sheet

private extension PlaylistsView {

    var createPlaylistSheet: some View {
        NavigationStack {
            Form {
                Section("Playlist Name") {
                    TextField("Name", text: $newName)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        didCreatePlaylist = false
                        showingCreate = false
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        createPlaylist()
                    }
                    .bold()
                    .disabled(
                        newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .presentationDetents([.medium])
    }

    func createPlaylist() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            _ = try repo.createPlaylist(name: name)
            didCreatePlaylist = true
            showingCreate = false
        } catch {
            didCreatePlaylist = false
            showPlaylistsToast(error.localizedDescription, tone: .error)
        }
    }

    func handleCreateDismiss() {
        if didCreatePlaylist {
            showPlaylistsToast("Playlist created", tone: .success)
        }

        didCreatePlaylist = false
        newName = ""
    }
}

// MARK: - Toast Emission

private extension PlaylistsView {

    func showPlaylistsToast(_ message: String, tone: ToastTone) {
        switch tone {
        case .success:
            toastCoordinator.showSuccess(
                message,
                style: .globalTop
            )

        case .info:
            toastCoordinator.showInfo(
                message,
                style: .globalTop
            )

        case .error:
            toastCoordinator.showError(
                message,
                style: .globalTop
            )
        }
    }
}
