//
//  TrackRepository.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  TrackRepository.swift
//  IceBox
//

import CoreData
import Foundation

@MainActor
final class TrackRepository {

    // MARK: - core

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - create

    @discardableResult
    func makeTrack(
        title: String,
        artist: String?,
        duration: Double,
        filePath: String,
        artworkData: Data? = nil
    ) -> Track {

        let track = Track(context: context)
        track.id = UUID()
        track.title = normalize(title)
        track.artist = normalizeOptional(artist)
        track.duration = max(0, duration)
        track.filePath = filePath
        track.artworkData = artworkData
        track.createdAt = Date()
        track.updatedAt = Date()

        return track
    }

    // MARK: - update

    func setArtwork(for track: Track, artworkData: Data?) {
        track.artworkData = artworkData
        track.updatedAt = Date()
    }

    func setMetadata(for track: Track, title: String, artist: String?) {
        track.title = normalize(title)
        track.artist = normalizeOptional(artist)
        track.updatedAt = Date()
    }

    // MARK: - delete

    func delete(_ track: Track) {
        context.delete(track)
    }

    // MARK: - fetch

    func fetchAllTracks() throws -> [Track] {
        let request: NSFetchRequest<Track> = Track.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    func fetchTrack(by id: UUID) throws -> Track? {
        let request: NSFetchRequest<Track> = Track.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func searchTracks(query: String) throws -> [Track] {
        let q = normalize(query)
        guard !q.isEmpty else { return try fetchAllTracks() }

        let request: NSFetchRequest<Track> = Track.fetchRequest()
        request.predicate = NSPredicate(
            format: "title CONTAINS[cd] %@ OR artist CONTAINS[cd] %@",
            q,
            q
        )
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        return try context.fetch(request)
    }

    // MARK: - persistence

    func saveIfNeeded() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    // MARK: - helpers

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeOptional(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = normalize(text)
        return trimmed.isEmpty ? nil : trimmed
    }
}
