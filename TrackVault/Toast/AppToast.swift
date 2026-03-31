//
//  AppToast.swift
//  IceBox
//

import Foundation

// MARK: - presentation style

/// Controls where a toast should appear.
///
/// This is the key part of the new Option B system:
/// one shared coordinator, but different screens can present
/// the toast in different inline regions.
enum ToastPresentationStyle: Equatable {
    case globalTop
    case libraryInline
    case playlistInline
}

// MARK: - tone

/// Defines the semantic meaning of the toast.
/// This is useful now for duration rules and later if you want
/// different visuals for success / info / error.
enum ToastTone: Equatable {
    case success
    case info
    case error
}

// MARK: - model

/// Shared toast payload used by the coordinator and host views.
///
/// The coordinator owns the active toast.
/// Host views decide whether to render it based on `style`.
struct AppToast: Identifiable, Equatable {
    let id: UUID
    let message: String
    let tone: ToastTone
    let style: ToastPresentationStyle
    let duration: TimeInterval

    init(
        id: UUID = UUID(),
        message: String,
        tone: ToastTone,
        style: ToastPresentationStyle,
        duration: TimeInterval
    ) {
        self.id = id
        self.message = message
        self.tone = tone
        self.style = style
        self.duration = duration
    }
}
