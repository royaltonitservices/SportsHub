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
            VStack(spacing: 0) {
                
                // --------------------------------------------------------
                // PLAYER IDENTITY SELECTOR
                // --------------------------------------------------------
                VStack(spacing: 12) {
                    Text("You are:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        ForEach(viewModel.players) { player in
                            Button {
                                viewModel.currentPlayerID = player.id
                            } label: {
                                Text("I am \(player.name)")
                                    .font(.headline)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        viewModel.currentPlayerID == player.id
                                            ? Color.blue
                                            : Color.gray.opacity(0.2)
                                    )
                                    .foregroundStyle(
                                        viewModel.currentPlayerID == player.id
                                            ? .white
                                            : .primary
                                    )
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 16)
                .background(Color(.systemGroupedBackground))
                
                Picker("Sport", selection: $viewModel.selectedSport) {
                    Text("Basketball").tag(Sport.basketball)
                    Text("Football").tag(Sport.football)
                    Text("Soccer").tag(Sport.soccer)
                    Text("Tennis").tag(Sport.tennis)
                }
                .pickerStyle(.segmented)
                .padding()
                
                List {
                    
                    // --------------------------------------------------------
                    // SECTION 1: Players
                    // --------------------------------------------------------
                    Section("Players") {
                        ForEach(viewModel.players) { player in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(player.name)
                                        .font(.headline)
                                    
                                    Text(player.rankLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(String(format: "%.0f", player.rating))
                                    .font(.headline)
                                    .monospacedDigit()
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
