//
//  FileAudioImporter.swift
//  IceBox
//

import Foundation
import UniformTypeIdentifiers

enum FileAudioImportError: LocalizedError {
    case unsupportedType
    case createDirectoryFailed
    case copyFailed
    case moveFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedType: return "unsupported file type"
        case .createDirectoryFailed: return "unable to prepare storage"
        case .copyFailed: return "unable to stage file"
        case .moveFailed: return "unable to commit file"
        case .deleteFailed: return "unable to discard staged file"
        }
    }
}

final class FileAudioImporter {

    private enum Paths {
        static let stagingFolder = "ImportStaging"
        static let audioFolder = "Audio"
    }

    static let supportedTypes: [UTType] = [
        .mp3,
        .mpeg4Audio,
        .wav,
        .aiff,
        .audio
    ]

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private var documentsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var stagingDir: URL {
        documentsDir.appendingPathComponent(Paths.stagingFolder, isDirectory: true)
    }

    private var audioDir: URL {
        documentsDir.appendingPathComponent(Paths.audioFolder, isDirectory: true)
    }

    // MARK: - public api

    func makeStagingURL(fileExtension: String) throws -> URL {
        try ensureDirectoryExists(stagingDir)
        let ext = sanitizeExtension(fileExtension)
        let name = UUID().uuidString
        return ext.isEmpty
            ? stagingDir.appendingPathComponent(name)
            : stagingDir.appendingPathComponent(name).appendingPathExtension(ext)
    }

    func stageAudio(from sourceURL: URL) throws -> URL {
        try validateSupportedType(for: sourceURL)
        try ensureDirectoryExists(stagingDir)

        let ext = sourceURL.pathExtension
        let stagedURL = stagingDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        try stageCopy(from: sourceURL, to: stagedURL)
        return stagedURL
    }

    func stageFileForExtraction(from sourceURL: URL, preferredExtension: String? = nil) throws -> URL {
        try ensureDirectoryExists(stagingDir)

        let sourceExt = sourceURL.pathExtension
        let preferredExt = sanitizeExtension(preferredExtension ?? "")
        let extToUse = !preferredExt.isEmpty ? preferredExt : sourceExt

        let name = UUID().uuidString
        let stagedURL = extToUse.isEmpty
            ? stagingDir.appendingPathComponent(name)
            : stagingDir.appendingPathComponent(name).appendingPathExtension(extToUse)

        try stageCopy(from: sourceURL, to: stagedURL)
        return stagedURL
    }

    func commitStagedAudio(_ stagedURL: URL) throws -> URL {
        try ensureDirectoryExists(audioDir)

        let ext = stagedURL.pathExtension
        let name = UUID().uuidString
        let finalURL = ext.isEmpty
            ? audioDir.appendingPathComponent(name)
            : audioDir.appendingPathComponent(name).appendingPathExtension(ext)

        do {
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: stagedURL, to: finalURL)
            return finalURL
        } catch {
            throw FileAudioImportError.moveFailed
        }
    }

    func discardStagedAudio(_ stagedURL: URL) throws {
        guard fileManager.fileExists(atPath: stagedURL.path) else { return }
        do {
            try fileManager.removeItem(at: stagedURL)
        } catch {
            throw FileAudioImportError.deleteFailed
        }
    }

    // MARK: - helpers

    private func validateSupportedType(for url: URL) throws {
        guard !url.pathExtension.isEmpty else { throw FileAudioImportError.unsupportedType }
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            throw FileAudioImportError.unsupportedType
        }

        let ok = Self.supportedTypes.contains { type.conforms(to: $0) }
        guard ok else { throw FileAudioImportError.unsupportedType }
    }

    private func ensureDirectoryExists(_ dir: URL) throws {
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw FileAudioImportError.createDirectoryFailed
        }
    }

    /// Robust copy strategy:
    /// 1) Try direct FileManager copy (works well for Photos-exported temp files).
    /// 2) If that fails, try NSFileCoordinator read coordination (works well for Files/iCloud providers).
    private func stageCopy(from sourceURL: URL, to destURL: URL) throws {
        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }

            // Fast path: direct copy
            try fileManager.copyItem(at: sourceURL, to: destURL)
            return
        } catch {
            // Fall through to coordinated copy
        }

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        var coordinatorError: NSError?
        var copyError: Error?

        NSFileCoordinator().coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { readableURL in
            do {
                if self.fileManager.fileExists(atPath: destURL.path) {
                    try self.fileManager.removeItem(at: destURL)
                }
                try self.fileManager.copyItem(at: readableURL, to: destURL)
            } catch {
                copyError = error
            }
        }

        if coordinatorError != nil || copyError != nil {
            throw FileAudioImportError.copyFailed
        }
    }

    private func sanitizeExtension(_ ext: String) -> String {
        let trimmed = ext.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
    }
}
