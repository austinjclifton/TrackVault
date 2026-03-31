//
//  ImportCoordinator.swift
//  IceBox
//

import AVFoundation
import Foundation
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable
import _PhotosUI_SwiftUI

enum ImportCoordinatorError: LocalizedError {
    case invalidDuration
    case videoNotPlayable
    case unsupportedType
    case unreadableMedia

    var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "invalid media duration"
        case .videoNotPlayable:
            return "video is not playable"
        case .unsupportedType:
            return "unsupported file type"
        case .unreadableMedia:
            return "unable to read media"
        }
    }
}

struct ImportedTrackDraft: Sendable {
    let stagedURL: URL
    let durationSeconds: Double
    let suggestedTitle: String
    let suggestedArtist: String?
    let discard: @MainActor @Sendable () async -> Void
    let commit: @MainActor @Sendable () async throws -> String
}

private struct VideoFileExported: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            .init(url: received.file)
        }
    }
}

@MainActor
final class ImportCoordinator {

    private let fileImporter: FileAudioImporter
    private let videoExtractor: VideoAudioExtractor

    init(fileImporter: FileAudioImporter, videoExtractor: VideoAudioExtractor) {
        self.fileImporter = fileImporter
        self.videoExtractor = videoExtractor
    }

    // MARK: - SOC Entry Points (Views call these)

    /// Single entry point for Files picker URLs (audio or video).
    /// Views should not perform UTType routing or security-scope handling.
    func stageFromFiles(
        sourceURL: URL,
        title: String? = nil,
        artist: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ImportedTrackDraft {
        let type = UTType(filenameExtension: sourceURL.pathExtension)

        if type?.conforms(to: .audio) == true {
            return try await stageFromFilesAudio(
                sourceURL: sourceURL,
                title: title,
                artist: artist
            )
        }

        if type?.conforms(to: .movie) == true {
            return try await stageFromVideo(
                videoURL: sourceURL,
                title: title,
                artist: artist,
                onProgress: onProgress
            )
        }

        throw ImportCoordinatorError.unsupportedType
    }

    /// Single entry point for Photos videos (ex: screen recordings).
    /// Coordinator owns transferable loading + staging into app-managed storage.
    func stageFromPhotosVideo(
        item: PhotosPickerItem,
        title: String? = nil,
        artist: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ImportedTrackDraft {
        guard let exported = try await item.loadTransferable(type: VideoFileExported.self) else {
            throw ImportCoordinatorError.unreadableMedia
        }

        // Stage Photos-exported file into our staging folder (single source of truth).
        let ext = exported.url.pathExtension.isEmpty ? "mov" : exported.url.pathExtension
        let stagedVideoURL = try fileImporter.stageFileForExtraction(
            from: exported.url,
            preferredExtension: ext
        )

        return try await stageFromVideo(
            videoURL: stagedVideoURL,
            title: title,
            artist: artist,
            onProgress: onProgress
        )
    }

    // MARK: - Internal Helpers (import domain)

    func stageFromFilesAudio(
        sourceURL: URL,
        title: String? = nil,
        artist: String? = nil
    ) async throws -> ImportedTrackDraft {
        let stagedURL = try fileImporter.stageAudio(from: sourceURL)

        do {
            let duration = try await Self.loadDurationSeconds(for: stagedURL)
            guard duration.isFinite, duration >= 0 else { throw ImportCoordinatorError.invalidDuration }

            return makeDraft(
                stagedURL: stagedURL,
                durationSeconds: duration,
                title: resolveTitle(provided: title, fallbackURL: sourceURL),
                artist: normalizeOptional(artist)
            )
        } catch {
            try? fileImporter.discardStagedAudio(stagedURL)
            throw error
        }
    }

    func stageFromVideo(
        videoURL: URL,
        title: String? = nil,
        artist: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ImportedTrackDraft {

        let report: @Sendable (Double) -> Void = { value in
            onProgress?(min(max(value, 0), 1))
        }

        report(0.05)
        try await ensureVideoIsPlayable(videoURL)
        report(0.1)

        let outputURL = try fileImporter.makeStagingURL(fileExtension: "m4a")

        do {
            let result = try await videoExtractor.extractAudio(
                from: videoURL,
                outputURL: outputURL,
                onProgress: { p in
                    Task { @MainActor in
                        report(0.1 + p * 0.9)
                    }
                }
            )

            guard result.duration.isFinite, result.duration >= 0 else {
                try? fileImporter.discardStagedAudio(result.stagedURL)
                throw ImportCoordinatorError.invalidDuration
            }

            return makeDraft(
                stagedURL: result.stagedURL,
                durationSeconds: result.duration,
                title: resolveTitle(provided: title, fallbackURL: videoURL),
                artist: normalizeOptional(artist)
            )
        } catch {
            try? fileImporter.discardStagedAudio(outputURL)
            throw error
        }
    }

    // MARK: - Draft Factory

    private func makeDraft(
        stagedURL: URL,
        durationSeconds: Double,
        title: String,
        artist: String?
    ) -> ImportedTrackDraft {
        ImportedTrackDraft(
            stagedURL: stagedURL,
            durationSeconds: durationSeconds,
            suggestedTitle: title,
            suggestedArtist: artist,
            discard: {
                // Ensure we execute on the main actor and access the coordinator's importer safely
                try? await MainActor.run { [stagedURL] in
                    try? self.fileImporter.discardStagedAudio(stagedURL)
                }
            },
            commit: {
                // Ensure we execute on the main actor and access the coordinator's importer safely
                let finalURL: URL = try await MainActor.run { [stagedURL] in
                    try self.fileImporter.commitStagedAudio(stagedURL)
                }
                return AudioFileResolver.normalizeStoredPath(finalURL.path)
            }
        )
    }

    // MARK: - Helpers

    private func ensureVideoIsPlayable(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        guard playable else { throw ImportCoordinatorError.videoNotPlayable }
    }

    private static func loadDurationSeconds(for audioURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: audioURL)
        let time = try await asset.load(.duration)
        return CMTimeGetSeconds(time)
    }

    private func resolveTitle(provided: String?, fallbackURL: URL) -> String {
        let trimmed = normalize(provided ?? "")
        if !trimmed.isEmpty { return trimmed }
        return fallbackURL.deletingPathExtension().lastPathComponent
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeOptional(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = normalize(text)
        return trimmed.isEmpty ? nil : trimmed
    }
}

