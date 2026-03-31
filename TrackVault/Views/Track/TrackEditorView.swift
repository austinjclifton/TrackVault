//
//  TrackEditorView.swift
//  IceBox
//

import CoreData
import PhotosUI
import SwiftUI

enum TrackEditorMode {
    case draft(ImportedTrackDraft)
    case existing(Track)

    var title: String {
        switch self {
        case .draft: return "Add Track"
        case .existing: return "Edit Track"
        }
    }
}

struct ArtistField: Identifiable, Equatable {
    let id = UUID()
    var name: String
}

struct TrackEditorView: View {

    // MARK: - core

    let mode: TrackEditorMode
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AudioPlayer

    // MARK: - state

    @State private var title: String
    @State private var artists: [ArtistField]

    @State private var artworkItem: PhotosPickerItem?
    @State private var artworkData: Data?

    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var artworkLoadTask: Task<Void, Never>?
    @State private var artworkLoadToken = UUID()

    // MARK: - init

    init(mode: TrackEditorMode, onFinish: @escaping () -> Void = {}) {
        self.mode = mode
        self.onFinish = onFinish

        switch mode {
        case .draft:
            _title = State(initialValue: "")
            _artists = State(initialValue: [ArtistField(name: "")])
            _artworkData = State(initialValue: nil)

        case .existing(let track):
            _title = State(initialValue: track.title)
            _artists = State(initialValue: Self.makeArtistFields(from: track.artist))
            _artworkData = State(initialValue: track.artworkData)
        }
    }

    // MARK: - body

    var body: some View {
        NavigationStack {
            Form {
                artworkSection
                titleSection
                artistsSection
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .disabled(isSaving)
            .alert(
                "Save Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: artworkItem) { _, newItem in
                guard let newItem else { return }
                loadArtwork(from: newItem)
            }
            .onDisappear {
                artworkLoadTask?.cancel()
                artworkLoadTask = nil
            }
        }
    }
}

// MARK: - toolbar

private extension TrackEditorView {

    var toolbar: some ToolbarContent {
        Group {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    if case .draft(let draft) = mode {
                        Task { await draft.discard() }
                    }
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task { await save() }
                }
                .bold()
                .disabled(isSaveDisabled)
            }
        }
    }

    var isSaveDisabled: Bool {
        normalizeTitle(title).isEmpty || isSaving
    }
}

// MARK: - artwork

private extension TrackEditorView {

    var artworkSection: some View {
        Section {
            HStack(spacing: 16) {
                artworkPreview

                PhotosPicker(
                    selection: $artworkItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text("Choose Artwork")
                }
            }
        }
    }

    @ViewBuilder
    var artworkPreview: some View {
        if let artworkData, let image = UIImage(data: artworkData) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(radius: 4)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.gray.opacity(0.2))
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
        }
    }

    func loadArtwork(from item: PhotosPickerItem) {
        artworkLoadTask?.cancel()

        let token = UUID()
        artworkLoadToken = token

        artworkLoadTask = Task {
            let data = try? await item.loadTransferable(type: Data.self)
            guard !Task.isCancelled, artworkLoadToken == token else { return }
            artworkData = data
        }
    }
}

// MARK: - title

private extension TrackEditorView {

    var titleSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Song title", text: $title)
                    .font(.body)
                    .textInputAutocapitalization(.words)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - artists

private extension TrackEditorView {

    var artistsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Artists")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach($artists.indices, id: \.self) { index in
                    TextField(
                        index == 0 ? "Primary artist" : "Additional artist",
                        text: $artists[index].name
                    )
                    .textInputAutocapitalization(.words)
                    .onChange(of: artists[index].name) { _, newValue in
                        handleArtistEdit(at: index, newValue: newValue)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    func handleArtistEdit(at index: Int, newValue: String) {
        let trimmed = normalizeField(newValue)

        if index == artists.count - 1, !trimmed.isEmpty {
            artists.append(ArtistField(name: ""))
            return
        }

        if trimmed.isEmpty,
           index < artists.count - 1,
           artists.count > 1 {
            artists.remove(at: index)
        }
    }
}

// MARK: - save

private extension TrackEditorView {

    @MainActor
    func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let finalTitle = normalizeTitle(title)
        guard !finalTitle.isEmpty else {
            errorMessage = "title is required"
            return
        }

        let artistString = buildArtistString(from: artists)

        do {
            switch mode {

            case .draft(let draft):
                try await container.libraryStore.saveDraftAsTrack(
                    draft,
                    title: finalTitle,
                    artist: artistString,
                    artworkData: artworkData
                )

            case .existing(let track):
                track.title = finalTitle
                track.artist = artistString
                track.artworkData = artworkData
                track.updatedAt = Date()

                if context.hasChanges {
                    try context.save()
                }

                player.refreshNowPlaying(from: track)
            }

            dismiss()
            onFinish()

        } catch {
            errorMessage = mapSaveError(error)
        }
    }

    func mapSaveError(_ error: Error) -> String {
        let ns = error as NSError

        if ns.domain == NSCocoaErrorDomain {
            return "unable to save changes"
        }

        if String(describing: error).lowercased().contains("permission") {
            return "permission error while saving"
        }

        return "save failed"
    }
}

// MARK: - helpers

private extension TrackEditorView {

    static func makeArtistFields(from stored: String?) -> [ArtistField] {
        let parts = (stored ?? "")
            .split(separator: ",")
            .map { normalizeField(String($0)) }
            .filter { !$0.isEmpty }

        if parts.isEmpty {
            return [ArtistField(name: "")]
        }

        return parts.map { ArtistField(name: $0) } + [ArtistField(name: "")]
    }

    func normalizeTitle(_ text: String) -> String {
        normalizeField(text)
    }

    static func normalizeField(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizeField(_ text: String) -> String {
        Self.normalizeField(text)
    }

    func buildArtistString(from fields: [ArtistField]) -> String? {
        let cleaned = fields
            .map { normalizeField($0.name) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else { return nil }

        // avoid commas in artist names since storage uses comma separation
        let sanitized = cleaned.map { $0.replacingOccurrences(of: ",", with: "") }
        return sanitized.joined(separator: ", ")
    }
}
