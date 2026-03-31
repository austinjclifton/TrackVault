import CoreData
import Foundation

@objc(PlaylistTrack)
public final class PlaylistTrack: NSManagedObject {}

extension PlaylistTrack {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PlaylistTrack> {
        NSFetchRequest<PlaylistTrack>(entityName: "PlaylistTrack")
    }
}

@MainActor
extension PlaylistTrack: Identifiable {}

// MARK: - properties

extension PlaylistTrack {

    @NSManaged public var id: UUID

    // required relationships enforced by the data model
    @NSManaged public var playlist: Playlist
    @NSManaged public var track: Track
}

