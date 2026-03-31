//
//  PlaylistTile.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  PlaylistTile.swift
//  IceBox
//

import SwiftUI

// MARK: - Playlist Tile

struct PlaylistTile: View {

    @ObservedObject var playlist: Playlist

    private let artworkSize: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            artwork
                .overlay(alignment: .topTrailing) {
                    if playlist.isPinned {
                        pinnedBadge
                    }
                }

            metadata
        }
        .contentShape(Rectangle()) // full tile is tappable
    }
}

// MARK: - Subviews

private extension PlaylistTile {

    var artwork: some View {
        PlaylistArtwork(
            artworkData: playlist.artworkData,
            size: artworkSize
        )
    }

    var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playlist.name)
                .font(.headline)
                .lineLimit(1)

            Text(songCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var pinnedBadge: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 13, weight: .semibold))
            .padding(6)
            .background(.ultraThinMaterial, in: Circle())
            .padding(8)
    }
}

// MARK: - Computed

private extension PlaylistTile {

    var songCountText: String {
        let count = playlist.tracksArray.count
        return "\(count) \(count == 1 ? "song" : "songs")"
    }
}

// MARK: - Artwork View (Private)

private struct PlaylistArtwork: View {

    let artworkData: Data?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

// MARK: - Artwork Helpers

private extension PlaylistArtwork {

    var image: UIImage? {
        guard
            let artworkData,
            let image = UIImage(data: artworkData)
        else { return nil }

        return image
    }

    var placeholder: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.65),
                Color.accentColor.opacity(0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "music.note.list")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
