import CoreData
import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {

    // MARK: - dependencies

    private var context: NSManagedObjectContext
    private var trackRepo: TrackRepository
    private var playlistRepo: PlaylistRepository

    // MARK: - init

    init(context: NSManagedObjectContext) {
        self.context = context
        self.trackRepo = TrackRepository(context: context)
        self.playlistRepo = PlaylistRepository(context: context)
    }

    // MARK: - context sync

    func updateContextIfNeeded(_ newContext: NSManagedObjectContext) {
        guard context !== newContext else { return }
        context = newContext
        trackRepo = TrackRepository(context: newContext)
        playlistRepo = PlaylistRepository(context: newContext)
    }

    // MARK: - playlists

    @discardableResult
    func createPlaylist(name: String) throws -> Playlist? {
        let trimmed = TrackSearch.normalize(name)
        guard !trimmed.isEmpty else { return nil }
        return try playlistRepo.createPlaylist(name: trimmed)
    }

    func addTrack(_ track: Track, to playlist: Playlist) throws {
        try playlistRepo.addTrack(track, to: playlist)
    }

    func removeTrack(_ track: Track, from playlist: Playlist) throws {
        try playlistRepo.removeTrack(track, from: playlist)
    }

    func deletePlaylist(_ playlist: Playlist) throws {
        try playlistRepo.deletePlaylist(playlist)
    }

    // MARK: - tracks

    func saveDraftAsTrack(
        _ draft: ImportedTrackDraft,
        title: String,
        artist: String?,
        artworkData: Data?
    ) async throws {

        let trimmedTitle = TrackSearch.normalize(title)
        let finalTitle = trimmedTitle.isEmpty ? draft.suggestedTitle : trimmedTitle

        let trimmedArtist = artist.map(TrackSearch.normalize)
        let finalArtist = (trimmedArtist?.isEmpty == false) ? trimmedArtist : nil

        let storedPath = try await draft.commit()

        let created = trackRepo.makeTrack(
            title: finalTitle,
            artist: finalArtist,
            duration: draft.durationSeconds,
            filePath: storedPath,
            artworkData: artworkData
        )

        do {
            try trackRepo.saveIfNeeded()
        } catch {
            context.delete(created)
            context.rollback()

            if let url = try? AudioFileResolver.audioURL(for: storedPath) {
                try? FileManager.default.removeItem(at: url)
            }

            throw error
        }
    }

    func saveIfNeeded() throws {
        try trackRepo.saveIfNeeded()
    }

    // MARK: - searching

    enum TrackFilter: String, CaseIterable, Hashable {
        case title
        case artist
    }

    func filteredTracks(
        from tracks: [Track],
        query: String,
        filter: TrackFilter
    ) -> [Track] {
        TrackSearch.filteredTracks(from: tracks, query: query, filter: filter)
    }

    func sortTracks(_ tracks: [Track], by filter: TrackFilter) -> [Track] {
        TrackSearch.sortTracks(tracks, by: filter)
    }
}

// MARK: - track search

private struct TrackSearch {

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeQuery(_ text: String) -> String {
        normalize(text).lowercased()
    }

    static func filteredTracks(
        from tracks: [Track],
        query: String,
        filter: LibraryStore.TrackFilter
    ) -> [Track] {

        let q = normalizeQuery(query)

        let base = q.isEmpty ? tracks : tracks.filter { track in
            switch filter {
            case .title:
                return track.displayTitle.lowercased().contains(q)

            case .artist:
                return track.displayArtist.lowercased().contains(q)
            }
        }

        return sortTracks(base, by: filter)
    }

    static func sortTracks(_ tracks: [Track], by filter: LibraryStore.TrackFilter) -> [Track] {
        tracks.sorted { lhs, rhs in
            switch filter {
            case .title:
                let titleCompare = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
                if titleCompare != .orderedSame {
                    return titleCompare == .orderedAscending
                }

                return lhs.displayArtist.localizedCaseInsensitiveCompare(rhs.displayArtist) == .orderedAscending

            case .artist:
                let artistCompare = lhs.displayArtist.localizedCaseInsensitiveCompare(rhs.displayArtist)
                if artistCompare != .orderedSame {
                    return artistCompare == .orderedAscending
                }

                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
        }
    }
}
