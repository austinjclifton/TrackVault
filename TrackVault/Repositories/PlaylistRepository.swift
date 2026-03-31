//
//  PlaylistRepository.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  PlaylistRepository.swift
//  IceBox
//

import CoreData
import Foundation

@MainActor
final class PlaylistRepository {

    // MARK: - Core

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Create

    func createPlaylist(name: String) throws -> Playlist {
        let trimmed = normalizeName(name)
        guard !trimmed.isEmpty else { throw RepoError.invalidName }

        let now = Date()
        let playlist = Playlist(context: context)
        playlist.id = UUID()
        playlist.name = trimmed
        playlist.createdAt = now
        playlist.updatedAt = now
        playlist.isPinned = false
        playlist.lastPlayedAt = now

        do {
            try saveIfNeeded()
            return playlist
        } catch {
            context.rollback() // removes the inserted playlist from the context
            throw error
        }
    }

    // MARK: - Update

    func updatePlaylist(
        _ playlist: Playlist,
        name: String,
        artworkData: Data?
    ) throws {
        let trimmed = normalizeName(name)
        guard !trimmed.isEmpty else { throw RepoError.invalidName }

        playlist.name = trimmed
        playlist.artworkData = artworkData
        playlist.updatedAt = Date()

        try saveIfNeeded()
    }

    // MARK: - Pinning

    func togglePin(_ playlist: Playlist) throws {
        playlist.isPinned.toggle()
        playlist.updatedAt = Date()
        try saveIfNeeded()
    }

    // MARK: - Recency

    func markPlayed(_ playlist: Playlist, at date: Date = Date()) throws {
        playlist.lastPlayedAt = date
        playlist.updatedAt = date
        try saveIfNeeded()
    }

    // MARK: - Add Tracks

    @discardableResult
    func addTrack(_ track: Track, to playlist: Playlist) throws -> Bool {
        guard !playlist.contains(track) else { return false }

        let orderedItems = playlist.mutableOrderedSetValue(forKey: #keyPath(Playlist.items))

        let item = PlaylistTrack(context: context)
        item.id = UUID()
        item.track = track
        item.playlist = playlist

        orderedItems.add(item)

        playlist.updatedAt = Date()
        try saveIfNeeded()
        return true
    }

    @discardableResult
    func add(tracks: [Track], to playlist: Playlist) throws -> Int {
        guard !tracks.isEmpty else { return 0 }

        let orderedItems = playlist.mutableOrderedSetValue(forKey: #keyPath(Playlist.items))

        var added = 0
        for track in tracks where !playlist.contains(track) {
            let item = PlaylistTrack(context: context)
            item.id = UUID()
            item.track = track
            item.playlist = playlist
            orderedItems.add(item)
            added += 1
        }

        guard added > 0 else { return 0 }

        playlist.updatedAt = Date()
        try saveIfNeeded()
        return added
    }

    // MARK: - Remove Tracks

    func removeTrack(_ track: Track, from playlist: Playlist) throws {
        let orderedItems = playlist.mutableOrderedSetValue(forKey: #keyPath(Playlist.items))

        let idx = indexOfTrack(track, in: orderedItems)
        guard let idx else { return }

        if let item = orderedItems.object(at: idx) as? PlaylistTrack {
            orderedItems.removeObject(at: idx)
            context.delete(item)
        }

        playlist.updatedAt = Date()
        try saveIfNeeded()
    }

    // MARK: - Delete

    func deletePlaylist(_ playlist: Playlist) throws {
        context.delete(playlist)
        try saveIfNeeded()
    }

    // MARK: - Persistence

    private func saveIfNeeded() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    // MARK: - Helpers

    private func normalizeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func indexOfTrack(_ track: Track, in orderedItems: NSMutableOrderedSet) -> Int? {
        let trackId = track.objectID

        for i in 0..<orderedItems.count {
            guard let item = orderedItems.object(at: i) as? PlaylistTrack else { continue }
            if item.track.objectID == trackId {
                return i
            }
        }

        return nil
    }

    // MARK: - Errors

    enum RepoError: LocalizedError {
        case invalidName

        var errorDescription: String? {
            switch self {
            case .invalidName:
                return "Playlist name cannot be empty"
            }
        }
    }
}

