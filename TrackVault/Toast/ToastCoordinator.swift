import Foundation
import SwiftUI
import Combine

@MainActor
final class ToastCoordinator: ObservableObject {

    // MARK: - Published State

    /// The single active toast for the app.
    ///
    /// Multiple screens can host different toast regions,
    /// but they all read from this one shared source of truth.
    @Published private(set) var currentToast: AppToast?

    // MARK: - Private State

    private var dismissTask: Task<Void, Never>?

    // MARK: - Public API

    /// Shows a toast immediately.
    ///
    /// Behavior:
    /// - trims and ignores empty messages
    /// - replaces the current toast
    /// - cancels any previous dismiss task
    /// - auto-hides after the resolved duration
    func show(
        _ message: String,
        tone: ToastTone = .info,
        style: ToastPresentationStyle = .globalTop,
        duration: TimeInterval? = nil
    ) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let toast = AppToast(
            message: trimmed,
            tone: tone,
            style: style,
            duration: duration ?? defaultDuration(for: tone)
        )

        replaceCurrentToast(with: toast)
    }

    /// Convenience wrapper for add/create success.
    func showSuccess(
        _ message: String,
        style: ToastPresentationStyle = .globalTop,
        duration: TimeInterval? = nil
    ) {
        show(message, tone: .success, style: style, duration: duration)
    }

    /// Convenience wrapper for update/info.
    func showInfo(
        _ message: String,
        style: ToastPresentationStyle = .globalTop,
        duration: TimeInterval? = nil
    ) {
        show(message, tone: .info, style: style, duration: duration)
    }

    /// Convenience wrapper for delete/error/failure.
    func showError(
        _ message: String,
        style: ToastPresentationStyle = .globalTop,
        duration: TimeInterval? = nil
    ) {
        show(message, tone: .error, style: style, duration: duration)
    }

    /// Clears the current toast.
    ///
    /// If `id` is passed, the clear only happens if that exact toast
    /// is still active. This prevents stale dismiss tasks from clearing
    /// a newer replacement toast.
    func clear(id: UUID? = nil) {
        if let id {
            guard currentToast?.id == id else { return }
        }

        dismissTask?.cancel()
        dismissTask = nil

        withAnimation(.easeInOut(duration: 0.22)) {
            currentToast = nil
        }
    }
}

// MARK: - Helpers

private extension ToastCoordinator {

    func replaceCurrentToast(with toast: AppToast) {
        dismissTask?.cancel()
        dismissTask = nil

        withAnimation(.easeInOut(duration: 0.22)) {
            currentToast = toast
        }

        scheduleDismiss(for: toast)
    }

    func scheduleDismiss(for toast: AppToast) {
        let toastID = toast.id
        let duration = max(toast.duration, 0.1)

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))

            guard !Task.isCancelled else { return }

            await self?.clear(id: toastID)
        }
    }

    func defaultDuration(for tone: ToastTone) -> TimeInterval {
        switch tone {
        case .success, .info, .error:
            return 2.8
        }
    }
}
