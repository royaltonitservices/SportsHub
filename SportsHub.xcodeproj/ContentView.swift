//
//  ContentView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 2/17/26.
//
//  Friday demo interface.
//  Shows players + ratings, a Simulate Match button, and a live match log.

import SwiftUI

struct ContentView: View {

    @State private var viewModel = DemoViewModel()

    var body: some View {
        NavigationStack {
            List {

                // --------------------------------------------------------
                // SECTION: Players
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
                // SECTION: Action
                // --------------------------------------------------------
                Section("Action") {
                    Button("Simulate Match") {
                        viewModel.simulateMatch()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                // --------------------------------------------------------
                // SECTION: Match Log
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
    }
}

#Preview {
    ContentView()
}
