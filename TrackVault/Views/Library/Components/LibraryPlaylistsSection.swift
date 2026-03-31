//
//  LibraryPlaylistsSection.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  LibraryPlaylistsSection.swift
//  IceBox
//

import SwiftUI

struct LibraryPlaylistsSection: View {

    // MARK: - input

    let playlists: [Playlist]
    @Binding var showPlaylists: Bool
    let onSelect: (Playlist) -> Void

    // MARK: - layout

    private enum Layout {
        static let cardWidth: CGFloat = 140
        static let spacing: CGFloat = 8
    }

    // MARK: - body

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            header

            if showPlaylists {
                content
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - header

private extension LibraryPlaylistsSection {

    var header: some View {
        HStack {
            Text("Playlists")
                .font(.headline)

            Spacer()

            Button {
                withAnimation(.easeInOut) {
                    showPlaylists.toggle()
                }
            } label: {
                Image(systemName: showPlaylists ? "chevron.down" : "chevron.right")
            }
            .accessibilityLabel(showPlaylists ? "Collapse playlists" : "Expand playlists")
        }
        .padding(8)
    }
}

// MARK: - content

private extension LibraryPlaylistsSection {

    @ViewBuilder
    var content: some View {
        if playlists.isEmpty {
            emptyState
        } else {
            playlistsScroller
        }
    }

    var emptyState: some View {
        Text("No playlists yet")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    var playlistsScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Layout.spacing) {
                ForEach(playlists, id: \.objectID) { playlist in
                    playlistCell(for: playlist)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - playlist cell

private extension LibraryPlaylistsSection {

    func playlistCell(for playlist: Playlist) -> some View {
        Button {
            onSelect(playlist)
        } label: {
            PlaylistTile(playlist: playlist)
                .frame(width: Layout.cardWidth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(playlist.name))
    }
}
