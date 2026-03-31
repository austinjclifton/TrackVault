import CoreData
import Foundation

public final class Playlist: NSManagedObject {}

extension Playlist {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Playlist> {
        NSFetchRequest<Playlist>(entityName: "Playlist")
    }
}

extension Playlist {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var artworkData: Data?
    @NSManaged public var isPinned: Bool
    @NSManaged public var lastPlayedAt: Date?
    @NSManaged public var items: NSOrderedSet?
}

extension Playlist {
    public var itemsArray: [PlaylistTrack] {
        (items?.array as? [PlaylistTrack]) ?? []
    }

    public var tracksArray: [Track] {
        itemsArray.map(\.track)
    }

    public func contains(_ track: Track) -> Bool {
        let objectID = track.objectID
        return itemsArray.contains { $0.track.objectID == objectID }
    }
}
