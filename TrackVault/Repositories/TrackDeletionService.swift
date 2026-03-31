//
//  TrackDeletionService.swift
//  IceBox
//

import CoreData
import Foundation

enum TrackDeletionError: LocalizedError {
    case saveFailed
    case fileDeletionFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "unable to delete track"
        case .fileDeletionFailed:
            return "unable to delete audio file"
        }
    }
}

@MainActor
final class TrackDeletionService {

    private let context: NSManagedObjectContext
    private let fileManager: FileManager

    init(
        context: NSManagedObjectContext,
        fileManager: FileManager = .default
    ) {
        self.context = context
        self.fileManager = fileManager
    }

    func deleteTrack(_ track: Track) throws {
        // Best-effort resolve; missing file should not block deleting the record.
        let audioURL = try? AudioFileResolver.audioURL(for: track.filePath)

        // Try to delete file first to avoid leaving disk junk when DB deletion succeeds.
        if let audioURL, fileManager.fileExists(atPath: audioURL.path) {
            do {
                try fileManager.removeItem(at: audioURL)
            } catch {
                // If you’d rather still delete the DB record even when file delete fails,
                // change this to a DEBUG print and continue.
                throw TrackDeletionError.fileDeletionFailed
            }
        }

        context.delete(track)

        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            throw TrackDeletionError.saveFailed
        }
    }
}
