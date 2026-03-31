//
//  AudioPlayer.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


import AVFoundation
import Combine
import CoreData
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class AudioPlayer: NSObject, ObservableObject {

    struct NowPlayingMetadata: Equatable {
        let title: String
        let artist: String
        let artworkData: Data?
    }

    struct QueueItem: Identifiable, Equatable {
        let id: NSManagedObjectID
        let filePath: String
        let title: String
        let artist: String
        let artworkData: Data?
    }

    @Published private(set) var nowPlaying: NowPlayingMetadata?
    @Published private(set) var nowPlayingTrackID: NSManagedObjectID?

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var currentIndex: Int?

    @Published private(set) var lastError: String?

    var currentTrack: QueueItem? {
        guard let index = currentIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    private let tickInterval: TimeInterval = 0.25
    private let skipInterval: Double = 5
    private let restartThreshold: Double = 2.5
    private let previousTapWindow: TimeInterval = 0.5

    private var player: AVAudioPlayer?
    private var timer: AnyCancellable?
    private var remoteCommandsConfigured = false
    private var lastPreviousTap: Date?
    private var wasPlayingBeforeInterruption = false

    override init() {
        super.init()
        configureRemoteCommandsIfNeeded()
        configureAudioSessionNotifications()
        refreshRemoteCommandAvailability()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Queue

    func startQueue(_ tracks: [Track], startAt index: Int = 0) {
        lastError = nil

        let items = tracks.map(Self.makeQueueItem)

        guard !items.isEmpty, items.indices.contains(index) else {
            clearQueue()
            return
        }

        queue = items
        currentIndex = index
        attemptPlayCurrent()
    }

    func clearQueue() {
        stopPlayback(resetQueue: true)
        queue.removeAll()
        currentIndex = nil
        clearNowPlaying()
        refreshRemoteCommandAvailability()
    }

    func playNext() {
        guard !queue.isEmpty else { return }

        if let index = currentIndex {
            let nextIndex = index + 1
            currentIndex = nextIndex >= queue.count ? 0 : nextIndex
        } else {
            currentIndex = 0
        }

        attemptPlayCurrent()
    }

    func playPrevious() {
        guard !queue.isEmpty else { return }

        let now = Date()
        let timeSinceLastTap = now.timeIntervalSince(lastPreviousTap ?? .distantPast)
        lastPreviousTap = now

        if timeSinceLastTap < previousTapWindow {
            jumpToPreviousTrack()
            return
        }

        if currentTime > restartThreshold {
            seek(to: 0)
        } else {
            jumpToPreviousTrack()
        }
    }

    private func jumpToPreviousTrack() {
        guard !queue.isEmpty else { return }

        if let index = currentIndex {
            currentIndex = index == 0 ? queue.count - 1 : index - 1
        } else {
            currentIndex = 0
        }

        attemptPlayCurrent()
    }

    // MARK: - Playback

    func play() {
        lastError = nil

        guard let player else { return }

        player.play()
        isPlaying = true
        startTimerIfNeeded()
        updateNowPlayingPlaybackRate()
        refreshRemoteCommandAvailability()
    }

    func pause() {
        guard let player else { return }

        player.pause()
        isPlaying = false
        stopTimer()
        updateNowPlayingPlaybackRate()
        refreshRemoteCommandAvailability()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to time: Double) {
        guard let player else { return }

        let clampedTime = min(max(time, 0), player.duration)
        player.currentTime = clampedTime
        currentTime = clampedTime
        updateNowPlayingElapsedTime()
    }

    func skipForward() {
        seek(to: currentTime + skipInterval)
    }

    func skipBackward() {
        seek(to: currentTime - skipInterval)
    }

    private func attemptPlayCurrent() {
        do {
            try playCurrent()
        } catch {
            handlePlaybackError(error)
        }
    }

    private func playCurrent() throws {
        guard let item = currentTrack else { return }

        let url = try AudioFileResolver.audioURL(for: item.filePath)
        try load(url: url, item: item)
        play()
    }

    private func load(url: URL, item: QueueItem) throws {
        stopPlayback(resetQueue: false)
        try configureAudioSession()

        let newPlayer = try AVAudioPlayer(contentsOf: url)
        newPlayer.delegate = self
        newPlayer.prepareToPlay()

        player = newPlayer
        duration = newPlayer.duration
        currentTime = 0
        isPlaying = false

        nowPlayingTrackID = item.id
        applyNowPlayingSnapshot(from: item)
        refreshRemoteCommandAvailability()
    }

    private func stopPlayback(resetQueue: Bool) {
        player?.stop()
        player = nil

        isPlaying = false
        currentTime = 0
        duration = 0

        stopTimer()
        updateNowPlayingPlaybackRate()

        if resetQueue {
            nowPlayingTrackID = nil
        }
    }

    // MARK: - Now Playing

    func refreshNowPlaying(from track: Track) {
        guard nowPlayingTrackID == track.objectID else { return }
        applyNowPlayingSnapshot(from: Self.makeQueueItem(from: track))
    }

    private func applyNowPlayingSnapshot(from item: QueueItem) {
        nowPlaying = NowPlayingMetadata(
            title: item.title,
            artist: item.artist,
            artworkData: item.artworkData
        )

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    private func updateNowPlayingPlaybackRate() {
        guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    }

    private func updateNowPlayingElapsedTime() {
        guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        nowPlaying = nil
        nowPlayingTrackID = nil
    }

    private static func makeQueueItem(from track: Track) -> QueueItem {
        QueueItem(
            id: track.objectID,
            filePath: track.filePath,
            title: track.displayTitle,
            artist: track.displayArtist,
            artworkData: track.artworkData
        )
    }

    // MARK: - Timer

    private func startTimerIfNeeded() {
        guard timer == nil else { return }

        timer = Timer.publish(every: tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let player = self.player, player.isPlaying else { return }
                self.currentTime = player.currentTime
                self.updateNowPlayingElapsedTime()
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Remote Commands

    private func configureRemoteCommandsIfNeeded() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .commandFailed }
            self.play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .commandFailed }
            self.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, !self.queue.isEmpty else { return .commandFailed }
            self.playNext()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, !self.queue.isEmpty else { return .commandFailed }
            self.playPrevious()
            return .success
        }
    }

    private func refreshRemoteCommandAvailability() {
        let commandCenter = MPRemoteCommandCenter.shared()

        let hasPlayer = player != nil
        let hasQueue = !queue.isEmpty

        commandCenter.playCommand.isEnabled = hasPlayer && !isPlaying
        commandCenter.pauseCommand.isEnabled = hasPlayer && isPlaying
        commandCenter.togglePlayPauseCommand.isEnabled = hasPlayer
        commandCenter.nextTrackCommand.isEnabled = hasQueue
        commandCenter.previousTrackCommand.isEnabled = hasQueue
    }

    // MARK: - Audio Session

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    private func configureAudioSessionNotifications() {
        let notificationCenter = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        notificationCenter.addObserver(
            self,
            selector: #selector(handleSessionInterruptionNotification(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleSessionRouteChangeNotification(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )
    }

    @objc private func handleSessionInterruptionNotification(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.handleInterruption(notification)
        }
    }

    @objc private func handleSessionRouteChangeNotification(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.handleRouteChange(notification)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let interruptionType = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch interruptionType {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            pause()

        case .ended:
            let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)

            if options.contains(.shouldResume), wasPlayingBeforeInterruption {
                play()
            }

            wasPlayingBeforeInterruption = false

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let rawReason = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else {
            return
        }

        if reason == .oldDeviceUnavailable {
            pause()
        }
    }

    // MARK: - Errors

    private func handlePlaybackError(_ error: Error) {
        stopPlayback(resetQueue: false)
        refreshRemoteCommandAvailability()

        if let resolverError = error as? AudioFileResolverError {
            switch resolverError {
            case .fileNotFound:
                lastError = "audio file not found"
                clearNowPlaying()

            case .invalidPath:
                lastError = "invalid audio file path"
                clearNowPlaying()

            @unknown default:
                lastError = "audio file error"
                clearNowPlaying()
            }

            return
        }

        if (error as NSError).domain == NSOSStatusErrorDomain {
            lastError = "audio playback failed"
            return
        }

        lastError = "unable to play audio"
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard flag else {
                self.lastError = "playback ended unexpectedly"
                self.pause()
                return
            }

            self.playNext()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.handlePlaybackError(
                error ?? NSError(domain: "audioplayer.decode", code: -1)
            )
        }
    }
}
