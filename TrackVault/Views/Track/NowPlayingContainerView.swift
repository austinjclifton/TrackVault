//
//  NowPlayingContainerView.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  NowPlayingContainerView.swift
//  IceBox
//

import SwiftUI
import UIKit
import CoreData

// MARK: - Container

struct NowPlayingContainerView: View {

    @EnvironmentObject private var player: AudioPlayer

    private enum Detent {
        case pill
        case collapsed
    }

    @State private var detent: Detent = .pill
    @State private var dragTranslation: CGFloat = 0

    private enum Layout {
        static let sheetHeight: CGFloat = 420
        static let collapsedVisibleHeight: CGFloat = 200
        static let pillVisibleHeight: CGFloat = 40
        static let snapThreshold: CGFloat = 80
    }

    private var pillOffset: CGFloat {
        Layout.sheetHeight - Layout.pillVisibleHeight
    }

    private var collapsedOffset: CGFloat {
        Layout.sheetHeight - Layout.collapsedVisibleHeight
    }

    private var detentOffset: CGFloat {
        switch detent {
        case .pill:
            return pillOffset
        case .collapsed:
            return collapsedOffset
        }
    }

    private var yOffset: CGFloat {
        let raw = detentOffset + dragTranslation
        return min(max(raw, collapsedOffset), pillOffset)
    }

    var body: some View {
        VStack(spacing: 0) {

            Capsule()
                .fill(.secondary.opacity(0.45))
                .frame(width: 44, height: 6)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .accessibilityHidden(true)

            if player.nowPlaying != nil {
                NowPlayingSheetView()
            } else {
                idleState
            }
        }
        .frame(height: Layout.sheetHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(radius: 12)
        .offset(y: yOffset)
        .gesture(dragGesture)
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: player.nowPlaying) { _, newValue in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                detent = (newValue != nil) ? .collapsed : .pill
                dragTranslation = 0
            }
        }

        // Toast note:
        // This view no longer owns toast state or listens to `player.lastError`.
        // Player-related toast emission should happen in exactly one higher-level owner
        // so the app does not duplicate the same error toast in multiple places.
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {

                    if value.translation.height < -Layout.snapThreshold {
                        detent = .collapsed
                    } else if value.translation.height > Layout.snapThreshold {
                        detent = .pill
                    }

                    dragTranslation = 0
                }
            }
    }

    private var idleState: some View {
        VStack(spacing: 14) {

            Image(systemName: "music.note")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text("Nothing Playing")
                .font(.headline)

            Text("Pick a song to start listening")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.top, 24)
        .padding(.horizontal)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nothing playing")
    }
}

// MARK: - Sheet Content

private struct NowPlayingSheetView: View {

    @EnvironmentObject private var player: AudioPlayer

    @State private var sliderValue: Double = 0
    @State private var isDragging = false

    private let cache = ArtworkDecodeCache()

    var body: some View {
        VStack(spacing: 20) {

            headerRow
                .padding(.horizontal)

            scrubber
                .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .onAppear {
            sliderValue = player.currentTime
        }
        .onChange(of: player.currentTime) { _, newValue in
            guard !isDragging else { return }
            sliderValue = newValue
        }
    }
}

// MARK: - Subviews

private extension NowPlayingSheetView {

    var headerRow: some View {
        HStack(spacing: 16) {

            artwork
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {

                VStack(alignment: .leading, spacing: 4) {
                    Text(player.nowPlaying?.title ?? "Now Playing")
                        .font(.headline)
                        .lineLimit(1)

                    Text(player.nowPlaying?.artist ?? "Unknown Artist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                controlsRow
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(player.nowPlaying?.title ?? "Now Playing"), \(player.nowPlaying?.artist ?? "Unknown Artist")"
        )
    }

    var controlsRow: some View {
        HStack(spacing: 18) {

            Button {
                player.playPrevious()
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .disabled(player.queue.count <= 1)
            .accessibilityLabel("Previous track")

            Button {
                player.skipBackward()
            } label: {
                Image(systemName: "gobackward.5")
            }
            .accessibilityLabel("Skip backward 5 seconds")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 46))
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                player.skipForward()
            } label: {
                Image(systemName: "goforward.5")
            }
            .accessibilityLabel("Skip forward 5 seconds")

            Button {
                player.playNext()
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .disabled(player.queue.count <= 1)
            .accessibilityLabel("Next track")
        }
        .buttonStyle(.plain)
    }

    var scrubber: some View {
        VStack(spacing: 8) {

            Slider(
                value: $sliderValue,
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        player.seek(to: sliderValue)
                    }
                }
            )

            HStack {
                Text(format(player.currentTime))
                Spacer()
                Text(format(player.duration))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    var artwork: some View {
        Group {
            if let id = player.nowPlayingTrackID,
               let data = player.nowPlaying?.artworkData,
               let image = cache.image(for: id, data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.gray.opacity(0.25))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
}

// MARK: - Helpers

private extension NowPlayingSheetView {

    func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

// MARK: - Artwork Cache

private final class ArtworkDecodeCache {

    private var cache: [NSManagedObjectID: UIImage] = [:]
    private let limit = 32

    func image(for id: NSManagedObjectID, data: Data) -> UIImage? {
        if let existing = cache[id] { return existing }
        guard let image = UIImage(data: data) else { return nil }

        if cache.count >= limit {
            cache.removeAll(keepingCapacity: true)
        }

        cache[id] = image
        return image
    }
}
