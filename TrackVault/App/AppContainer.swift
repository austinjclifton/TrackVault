//
//  AppContainer.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


import Foundation
import CoreData
import SwiftUI
import UIKit
import Combine

@MainActor
final class AppContainer: ObservableObject {

    // MARK: - Constants

    private static let appearanceKey = "isDarkMode"

    private enum AppearanceTiming {
        static let snapshotDelay: TimeInterval = 0.05
        static let fadeDelay: TimeInterval = 0.06
        static let fadeDuration: TimeInterval = 0.35
    }

    // MARK: - Core

    let persistence: PersistenceController
    let viewContext: NSManagedObjectContext

    // MARK: - Appearance State

    @Published private(set) var isDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: Self.appearanceKey)
        }
    }

    @Published var appearanceSnapshot: UIImage?
    @Published private(set) var isReadyForAppearanceToggle = false

    var preferredColorScheme: ColorScheme? {
        isDarkMode ? .dark : .light
    }

    // MARK: - Dependencies

    let libraryStore: LibraryStore
    let trackRepository: TrackRepository
    let playlistRepository: PlaylistRepository
    let trackDeletionService: TrackDeletionService
    let artworkService: ArtworkService
    let importCoordinator: ImportCoordinator
    let audioPlayer: AudioPlayer

    // MARK: - Init

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
        self.viewContext = persistence.viewContext

        self.isDarkMode = UserDefaults.standard.bool(
            forKey: Self.appearanceKey
        )

        self.libraryStore = LibraryStore(context: viewContext)
        self.trackRepository = TrackRepository(context: viewContext)
        self.playlistRepository = PlaylistRepository(context: viewContext)
        self.trackDeletionService = TrackDeletionService(context: viewContext)
        self.artworkService = ArtworkService(context: viewContext)

        self.importCoordinator = ImportCoordinator(
            fileImporter: FileAudioImporter(),
            videoExtractor: VideoAudioExtractor()
        )

        self.audioPlayer = AudioPlayer()
    }

    // MARK: - Appearance Control

    func markAppearanceReady() {
        isReadyForAppearanceToggle = true
    }

    func toggleAppearance() {
        guard isReadyForAppearanceToggle else { return }

        takeSnapshot()

        DispatchQueue.main.asyncAfter(
            deadline: .now() + AppearanceTiming.snapshotDelay
        ) {
            self.isDarkMode.toggle()

            DispatchQueue.main.asyncAfter(
                deadline: .now() + AppearanceTiming.fadeDelay
            ) {
                withAnimation(.easeInOut(duration: AppearanceTiming.fadeDuration)) {
                    self.appearanceSnapshot = nil
                }
            }
        }
    }

    private func takeSnapshot() {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = scene.windows.first
        else { return }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        appearanceSnapshot = renderer.image { _ in
            window.drawHierarchy(
                in: window.bounds,
                afterScreenUpdates: true
            )
        }
    }
}
