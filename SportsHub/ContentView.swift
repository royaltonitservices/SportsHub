//
//  ContentView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 2/17/26.
//
//  Friday demo interface.
//  Shows players + ratings, a Simulate Match button, and a live match log.
//  Players and ratings are sourced from DemoAuthority via DemoViewModel.

import SwiftUI
import SportsHubCore

struct ContentView: View {

    @State private var viewModel = DemoViewModel()

    var body: some View {
        NavigationStack {
            List {

                // --------------------------------------------------------
                // SECTION 1: Players
                // --------------------------------------------------------
                Section("Players") {
                    ForEach(viewModel.players) { player in
                        HStack {
                            Text(player.name)
                                .font(.headline)
                            Spacer()
                            Text(String(format: "%.0f", player.rating))
                                .font(.headline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // --------------------------------------------------------
                // SECTION 2: Action
                // --------------------------------------------------------
                Section("Action") {
                    Button("Simulate Match") {
                        viewModel.simulateMatch()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                // --------------------------------------------------------
                // SECTION 3: Match Log
                // --------------------------------------------------------
                if !viewModel.matchLog.isEmpty {
                    Section("Match Log") {
                        ForEach(viewModel.matchLog) { entry in
                            HStack(spacing: 4) {
                                Text(entry.winnerName)
                                    .foregroundStyle(.green)
                                Text("beat")
                                    .foregroundStyle(.secondary)
                                Text(entry.loserName)
                                    .foregroundStyle(.red)
                                Spacer()
                                Text(String(format: "+%.0f", entry.ratingChange))
                                    .foregroundStyle(.green)
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("SportsHub Demo")
        }
        .task {
            await viewModel.startListening()
        }
    }
}

#Preview {
    ContentView()
}
