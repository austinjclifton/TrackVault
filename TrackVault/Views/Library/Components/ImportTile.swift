//
//  ImportTile.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  ImportTile.swift
//  IceBox
//

import SwiftUI

struct ImportTile: View {

    let title: String
    let subtitle: String
    let systemImage: String
    let backgroundColor: Color

    var body: some View {
        VStack(spacing: 12) {

            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)

            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .padding(.horizontal, 10)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
