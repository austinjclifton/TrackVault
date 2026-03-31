//
//  PersistenceController.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  PersistenceController.swift
//  IceBox
//

import CoreData

@MainActor
final class PersistenceController {

    static let shared = PersistenceController()

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "TrackVault")

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [description]
        }

        container.persistentStoreDescriptions.forEach { description in
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("core data failed to load \(error)")
            }
        }

        configureViewContext()
    }

    private func configureViewContext() {
        let ctx = container.viewContext
        ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        ctx.automaticallyMergesChangesFromParent = true
        ctx.shouldDeleteInaccessibleFaults = true
    }
}

