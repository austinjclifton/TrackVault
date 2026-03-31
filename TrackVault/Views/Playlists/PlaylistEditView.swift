//
//  PlaylistEditView.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  PlaylistEditView.swift
//  IceBox
//

import SwiftUI
import PhotosUI
import CoreData

struct PlaylistEditView: View {

    enum Result: Equatable {
        case saved
        case failed(String)
    }

    // MARK: - Dependencies

    @ObservedObject var playlist: Playlist

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var repo: PlaylistRepository {
        PlaylistRepository(context: context)
    }

    // MARK: - Output

    let onResult: (Result) -> Void

    // MARK: - Draft State

    @State private var name: String = ""
    @State private var artworkItem: PhotosPickerItem?
    @State private var artworkData: Data?
    @State private var isSaving = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {

                artworkSection
                nameSection

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .navigationTitle("Edit Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onAppear(perform: loadDraft)
        .onChange(of: artworkItem) { loadArtwork(from: $0) }
    }
}

// MARK: - Toolbar

private extension PlaylistEditView {

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {

        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                dismiss()
            }
            .disabled(isSaving)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                save()
            }
            .disabled(!hasChanges || isSaving)
        }
    }
}

// MARK: - Sections

private extension PlaylistEditView {

    var artworkSection: some View {
        VStack(spacing: 16) {

            artworkPreview

            PhotosPicker(
                selection: $artworkItem,
                matching: .images
            ) {
                Label("Choose Artwork", systemImage: "photo")
                    .font(.body.weight(.semibold))
            }
            .disabled(isSaving)
        }
        .frame(maxWidth: .infinity)
    }

    var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {

            Text("Playlist Name")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Playlist name", text: $name)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .disabled(isSaving)
        }
    }
}

// MARK: - Artwork Preview

private extension PlaylistEditView {

    var artworkPreview: some View {
        ZStack {
            if let data = artworkData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
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
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 220, height: 220)
        .clipShape(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }
}

// MARK: - Logic

private extension PlaylistEditView {

    func loadDraft() {
        name = playlist.name
        artworkData = playlist.artworkData
    }

    var hasChanges: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) != playlist.name
        || artworkData != playlist.artworkData
    }

    func loadArtwork(from item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    artworkData = data
                }
            }
        }
    }

    func save() {
        guard !isSaving else { return }
        isSaving = true

        do {
            try repo.updatePlaylist(
                playlist,
                name: name,
                artworkData: artworkData
            )
            onResult(.saved)
            dismiss()
        } catch {
            onResult(.failed(error.localizedDescription))
            isSaving = false
        }
    }
}
