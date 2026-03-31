//
//  ToastView.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


import SwiftUI

struct ToastView: View {

    let message: String

    private enum Layout {
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 10
        static let borderOpacity: CGFloat = 0.34
        static let highlightOpacity: CGFloat = 0.18
        static let shadowOpacity: CGFloat = 0.10
    }

    var body: some View {
        HStack(spacing: 8) {

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(.clear)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.primary.opacity(Layout.borderOpacity), lineWidth: 1.15)
                }
        )
        .shadow(color: .black.opacity(Layout.shadowOpacity), radius: 8, y: 2)
        .compositingGroup()
        .accessibilityLabel(message)
        .accessibilityAddTraits(.isStaticText)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
