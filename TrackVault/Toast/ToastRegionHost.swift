//
//  ToastRegionHost.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  ToastRegionHost.swift
//  IceBox
//

import SwiftUI

/// Shared host that renders the current toast only when the active
/// toast's presentation style matches this host region.
///
/// This supports the Option B architecture:
/// - one shared toast coordinator
/// - multiple screen-specific toast regions
struct ToastRegionHost: View {

    // MARK: - Dependencies

    @EnvironmentObject private var toastCoordinator: ToastCoordinator

    // MARK: - Configuration

    let style: ToastPresentationStyle
    let topPadding: CGFloat
    let horizontalPadding: CGFloat

    // MARK: - Init

    init(
        style: ToastPresentationStyle,
        topPadding: CGFloat = 0,
        horizontalPadding: CGFloat = 0
    ) {
        self.style = style
        self.topPadding = topPadding
        self.horizontalPadding = horizontalPadding
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let toast = matchingToast {
                ToastView(message: toast.message)
                    .padding(.top, topPadding)
                    .padding(.horizontal, horizontalPadding)
                    .id(toast.id)
            }
        }
    }
}

// MARK: - Helpers

private extension ToastRegionHost {

    var matchingToast: AppToast? {
        guard let toast = toastCoordinator.currentToast else { return nil }
        return toast.style == style ? toast : nil
    }
}
