import CoreData
import Foundation
import SwiftUI
import UIKit

public final class Track: NSManagedObject {}

extension Track {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Track> {
        NSFetchRequest<Track>(entityName: "Track")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var artist: String?
    @NSManaged public var duration: Double
    @NSManaged public var filePath: String
    @NSManaged public var artworkData: Data?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var playlistItems: Set<PlaylistTrack>
}

extension Track {
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Track" : trimmed
    }

    public var displayArtist: String {
        let trimmed = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Artist" : trimmed
    }

    public var displayDuration: String {
        let totalSeconds = max(0, Int(duration))
        return "\(totalSeconds / 60):" + String(format: "%02d", totalSeconds % 60)
    }
    
    public var formattedDuration: String {
        displayDuration
    }

    public var artworkImage: Image? {
        guard let data = artworkData, let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }
}
