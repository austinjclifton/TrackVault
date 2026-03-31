//
//  PlaylistTrackRow.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  PlaylistTrackRow.swift
//  IceBox
//

import SwiftUI

struct PlaylistTrackRow: View {

    let track: Track
    let showsSelection: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {

            artwork
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.body)
                    .lineLimit(1)

                Text(track.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Duration (middle-right)
            if let durationText = formattedDuration {
                Text(durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if showsSelection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artwork: some View {
        // If you later add an image source to Track (e.g., URL or Image), adapt this block accordingly.
        // For now, always show a placeholder to avoid referencing a non-existent property.
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.gray.opacity(0.2))
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }

    // MARK: - Duration Formatting

    private var formattedDuration: String? {
        let seconds = track.duration
        guard seconds.isFinite, seconds > 0 else { return nil }

        let total = Int(seconds)
        let minutes = total / 60
        let remainingSeconds = total % 60

        return "\(minutes):" + String(format: "%02d", remainingSeconds)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        if let duration = formattedDuration {
            return "\(track.displayTitle), \(track.displayArtist), \(duration)"
        } else {
            return "\(track.displayTitle), \(track.displayArtist)"
        }
    }
}

