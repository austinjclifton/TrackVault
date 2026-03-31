//
//  VideoAudioExtractor.swift
//  IceBox
//

import AVFoundation
import Foundation

// Errors specific to audio extraction operations in this file.
enum VideoAudioExtractionError: Error, LocalizedError, Equatable {
    case noAudioTrack
    case readerFailed
    case writerFailed
    case exportSetupFailed
    case exportFailed(underlying: Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "The selected video doesn't contain an audio track."
        case .readerFailed:
            return "Failed to read audio from the video asset."
        case .writerFailed:
            return "Failed to write extracted audio."
        case .exportSetupFailed:
            return "Unable to set up the audio export session."
        case .exportFailed(let underlying):
            return "Audio export failed: \(underlying.localizedDescription)"
        case .cancelled:
            return "The audio extraction was cancelled."
        }
    }

    static func == (lhs: VideoAudioExtractionError, rhs: VideoAudioExtractionError) -> Bool {
        switch (lhs, rhs) {
        case (.noAudioTrack, .noAudioTrack),
             (.readerFailed, .readerFailed),
             (.writerFailed, .writerFailed),
             (.exportSetupFailed, .exportSetupFailed),
             (.cancelled, .cancelled):
            return true
        case (.exportFailed(let l), .exportFailed(let r)):
            // Compare by localizedDescription as `Error` is not Equatable.
            return l.localizedDescription == r.localizedDescription
        default:
            return false
        }
    }
}

// Wrapper to allow capturing non-Sendable SDK types in @Sendable closures when usage is known to be safe.
private struct UncheckedSendable<T>: @unchecked Sendable { let value: T }

final class VideoAudioExtractor {

    struct Result {
        let stagedURL: URL
        let duration: Double
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    nonisolated(nonsending)
    func extractAudio(
        from videoURL: URL,
        outputURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Result {

        try Task.checkCancellation()
        let fm = self.fileManager

        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else { throw VideoAudioExtractionError.noAudioTrack }

        // Ensure clean output path before attempting either strategy
        try Self.removeFileIfExists(outputURL, fileManager: fm)

        // Prefer passthrough for AAC (fast path). If it fails, we fall back to export.
        if await Self.isAACEncoded(track: audioTrack) {
            do {
                try await Self.extractViaReaderWriterPassthrough(
                    asset: asset,
                    audioTrack: audioTrack,
                    outputURL: outputURL,
                    onProgress: onProgress,
                    fileManager: fm
                )

                let duration = try await Self.loadDuration(from: outputURL)
                return Result(stagedURL: outputURL, duration: duration)
            } catch {
                // Passthrough can fail for provider-backed assets or weird timelines.
                // Clean output and fall back to export unless cancelled.
                try? Self.removeFileIfExists(outputURL, fileManager: fm)
                if case .cancelled = (error as? VideoAudioExtractionError) {
                    throw error
                }
            }
        }

        return try await Self.extractViaExportSession(
            asset: asset,
            outputURL: outputURL,
            onProgress: onProgress,
            fileManager: fm
        )
    }

    // MARK: - reader writer passthrough

    nonisolated(nonsending)
    private static func extractViaReaderWriterPassthrough(
        asset: AVAsset,
        audioTrack: AVAssetTrack,
        outputURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        fileManager: FileManager
    ) async throws {

        try Task.checkCancellation()

        let reader: AVAssetReader
        let writer: AVAssetWriter

        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw VideoAudioExtractionError.readerFailed
        }

        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        } catch {
            throw VideoAudioExtractionError.writerFailed
        }

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        readerOutput.alwaysCopiesSampleData = false

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        writerInput.expectsMediaDataInRealTime = false

        guard reader.canAdd(readerOutput), writer.canAdd(writerInput) else {
            throw VideoAudioExtractionError.readerFailed
        }

        reader.add(readerOutput)
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else {
            throw VideoAudioExtractionError.readerFailed
        }

        writer.startSession(atSourceTime: .zero)

        let durationTime = try await asset.load(.duration)
        let totalSeconds = max(0.001, CMTimeGetSeconds(durationTime))

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let queue = DispatchQueue(label: "trackvault.audio.passthrough")

                // Capture objects by value in the closure (wrapped as unchecked Sendable for use in a @Sendable context).
                let safeReader = UncheckedSendable(value: reader)
                let safeWriter = UncheckedSendable(value: writer)
                let safeReaderOutput = UncheckedSendable(value: readerOutput)
                let safeWriterInput = UncheckedSendable(value: writerInput)

                var didResume = false
                func resumeOnce(_ result: Swift.Result<Void, Error>) {
                    guard !didResume else { return }
                    didResume = true
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let err):
                        continuation.resume(throwing: err)
                    }
                }

                safeWriterInput.value.requestMediaDataWhenReady(on: queue) {
                    while safeWriterInput.value.isReadyForMoreMediaData {

                        if Task.isCancelled {
                            safeReader.value.cancelReading()
                            safeWriter.value.cancelWriting()
                            resumeOnce(.failure(VideoAudioExtractionError.cancelled))
                            return
                        }

                        if safeReader.value.status == .failed {
                            resumeOnce(.failure(VideoAudioExtractionError.readerFailed))
                            return
                        }

                        if safeWriter.value.status == .failed {
                            resumeOnce(.failure(VideoAudioExtractionError.writerFailed))
                            return
                        }

                        if let sample = safeReaderOutput.value.copyNextSampleBuffer() {
                            guard safeWriterInput.value.append(sample) else {
                                resumeOnce(.failure(VideoAudioExtractionError.writerFailed))
                                return
                            }

                            let seconds = sample.presentationTimeStamp.seconds
                            onProgress?(min(seconds / totalSeconds, 1.0))
                            continue
                        }

                        safeWriterInput.value.markAsFinished()
                        safeWriter.value.finishWriting {
                            if safeWriter.value.status == .completed {
                                resumeOnce(.success(()))
                            } else if safeWriter.value.status == .cancelled {
                                resumeOnce(.failure(VideoAudioExtractionError.cancelled))
                            } else {
                                resumeOnce(.failure(VideoAudioExtractionError.writerFailed))
                            }
                        }
                        return
                    }
                }
            }
        } catch {
            // Ensure we don't leave partially written output on any error.
            try? Self.removeFileIfExists(outputURL, fileManager: fileManager)
            if case .cancelled = (error as? VideoAudioExtractionError) {
                throw VideoAudioExtractionError.cancelled
            }
            // Map any other error to our domain error.
            throw (error as? VideoAudioExtractionError) ?? VideoAudioExtractionError.writerFailed
        }

        if reader.status == .failed {
            try? Self.removeFileIfExists(outputURL, fileManager: fileManager)
            throw VideoAudioExtractionError.readerFailed
        }

        if writer.status == .failed {
            try? Self.removeFileIfExists(outputURL, fileManager: fileManager)
            throw VideoAudioExtractionError.writerFailed
        }
    }

    // MARK: - audio track inspection

    private static func isAACEncoded(track: AVAssetTrack) async -> Bool {
        // Use modern async loading for format descriptions to avoid deprecation.
        // Load as [CMFormatDescription] and then safely convert to [CMAudioFormatDescription]
        let cmFormats: [CMFormatDescription]
        do {
            cmFormats = try await track.load(.formatDescriptions)
        } catch {
            return false
        }
        guard !cmFormats.isEmpty else { return false }

        return cmFormats.contains { desc in
            // Ensure it's an audio format description before querying ASBD
            guard CMFormatDescriptionGetMediaType(desc) == kCMMediaType_Audio,
                  let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else {
                return false
            }
            let asbd = asbdPtr.pointee
            return asbd.mFormatID == kAudioFormatMPEG4AAC
        }
    }

    // MARK: - export session fallback

    nonisolated(nonsending)
    private static func extractViaExportSession(
        asset: AVAsset,
        outputURL: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        fileManager: FileManager
    ) async throws -> Result {

        try Task.checkCancellation()

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw VideoAudioExtractionError.exportSetupFailed
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a

        // Wrap non-Sendable exporter for use inside the concurrent Task safely.
        let safeExporter = UncheckedSendable(value: exporter)
        let progressHandler = onProgress // capture into a local for sendable closure use

        let progressTask = Task { @Sendable in
            for await state in safeExporter.value.states(updateInterval: 0.1) {
                if Task.isCancelled { break }
                if case .exporting(let p) = state {
                    progressHandler?(p.fractionCompleted)
                }
            }
        }

        do {
            try await exporter.export(to: outputURL, as: .m4a)
        } catch {
            progressTask.cancel()
            try? Self.removeFileIfExists(outputURL, fileManager: fileManager)
            if Task.isCancelled {
                throw VideoAudioExtractionError.cancelled
            }
            throw VideoAudioExtractionError.exportFailed(underlying: error)
        }

        progressTask.cancel()

        let duration = try await Self.loadDuration(from: outputURL)
        return Result(stagedURL: outputURL, duration: duration)
    }

    // MARK: - helpers

    private static func loadDuration(from url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let time = try await asset.load(.duration)
        return CMTimeGetSeconds(time)
    }

    private static func removeFileIfExists(_ url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

