//
//  ArtworkService.swift
//  IceBox
//

import CoreData
import Foundation
import UIKit

enum ArtworkServiceError: LocalizedError {
    case imageTooLarge(maxMB: Int, actualMB: Int)
    case invalidImageData
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .imageTooLarge(let maxMB, let actualMB):
            return "Artwork is too large (\(actualMB) MB). Max is \(maxMB) MB."
        case .invalidImageData:
            return "Artwork image data is invalid."
        case .compressionFailed:
            return "Unable to prepare artwork image."
        }
    }
}

@MainActor
final class ArtworkService {

    private let trackRepo: TrackRepository
    private let maxBytes: Int
    private let targetMaxDimension: CGFloat

    init(
        context: NSManagedObjectContext,
        maxBytes: Int = 6_000_000,
        targetMaxDimension: CGFloat = 1024
    ) {
        self.trackRepo = TrackRepository(context: context)
        self.maxBytes = maxBytes
        self.targetMaxDimension = targetMaxDimension
    }

    // MARK: - public api

    func applyArtwork(_ data: Data?, to track: Track) throws {
        let prepared = try prepareArtworkData(data)
        trackRepo.setArtwork(for: track, artworkData: prepared)
    }

    func removeArtwork(from track: Track) {
        trackRepo.setArtwork(for: track, artworkData: nil)
    }

    // MARK: - preparation

    func prepareArtworkData(_ data: Data?) throws -> Data? {
        guard let data else { return nil }
        if data.count <= maxBytes { return data }

        guard let image = UIImage(data: data) else {
            throw ArtworkServiceError.invalidImageData
        }

        let resized = resizeIfNeeded(image, maxDimension: targetMaxDimension)
        let compressed = try compressToFit(resized, maxBytes: maxBytes)

        if compressed.count > maxBytes {
            throw ArtworkServiceError.imageTooLarge(
                maxMB: bytesToMB(maxBytes),
                actualMB: bytesToMB(data.count)
            )
        }

        return compressed
    }

    private func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func compressToFit(_ image: UIImage, maxBytes: Int) throws -> Data {
        var q: CGFloat = 0.92
        var last: Data?

        for _ in 0..<10 {
            guard let data = image.jpegData(compressionQuality: q) else {
                throw ArtworkServiceError.compressionFailed
            }

            last = data
            if data.count <= maxBytes { return data }

            q = max(0.4, q - 0.08)
        }

        if let last { return last }
        throw ArtworkServiceError.compressionFailed
    }

    private func bytesToMB(_ bytes: Int) -> Int {
        max(1, Int(round(Double(bytes) / 1_000_000)))
    }
}
