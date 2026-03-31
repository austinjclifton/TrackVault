//
//  LibrarySearchBar.swift
//  TrackVault
//
//  Created by Austin Clifton on 3/24/26.
//


//
//  LibrarySearchBar.swift
//  IceBox
//

import SwiftUI

struct LibrarySearchBar: View {

    @Binding var searchText: String
    @Binding var activeFilter: LibraryStore.TrackFilter

    var body: some View {
        HStack(spacing: 8) {

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(placeholderText, text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Menu {
                filterRow(.title, label: "Title")
                filterRow(.artist, label: "Artist")
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 8)
    }

    private var placeholderText: String {
        switch activeFilter {
        case .title:
            return "Search titles"
        case .artist:
            return "Search artists"
        }
    }

    private func filterRow(_ filter: LibraryStore.TrackFilter, label: String) -> some View {
        Button {
            activeFilter = filter
        } label: {
            if activeFilter == filter {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }
}
