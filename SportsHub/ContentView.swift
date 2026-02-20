//
//  ContentView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 2/17/26.
//
//  SportsHub Home Experience.
//  Product-focused interface showing player status, challenge action, and recent activity.

import SwiftUI
import SportsHubCore

struct ContentView: View {

    @State private var viewModel = DemoViewModel()
    @State private var highlightHeader = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // --------------------------------------------------------
                    // PLAYER IDENTITY SELECTOR (Compact)
                    // --------------------------------------------------------
                    HStack(spacing: 12) {
                        ForEach(viewModel.players) { player in
                            Button {
                                viewModel.currentPlayerID = player.id
                            } label: {
                                Text("I am \(player.name)")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
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
                    .padding(.top, 8)
                    
                    // --------------------------------------------------------
                    // SECTION 1: PLAYER HEADER
                    // --------------------------------------------------------
                    if let currentPlayer = viewModel.currentPlayer {
                        VStack(spacing: 16) {
                            
                            VStack(spacing: 8) {
                                Text("You are")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                Text(currentPlayer.name)
                                    .font(.system(size: 32, weight: .bold))
                            }
                            
                            HStack(spacing: 32) {
                                VStack(spacing: 4) {
                                    Text(viewModel.sportDisplayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "%.0f", currentPlayer.rating))
                                        .font(.title.bold())
                                        .monospacedDigit()
                                        .contentTransition(.numericText())
                                }
                                
                                VStack(spacing: 4) {
                                    Text("Rank")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(currentPlayer.rankLabel)
                                        .font(.title3.bold())
                                        .foregroundStyle(.blue)
                                        .contentTransition(.interpolate)
                                }
                            }
                        }
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .background(
                            Color(.systemGroupedBackground)
                                .overlay(
                                    highlightHeader
                                        ? Color.blue.opacity(0.15)
                                        : Color.clear
                                )
                        )
                        .cornerRadius(16)
                        .padding(.horizontal)
                        .animation(.easeInOut(duration: 0.3), value: currentPlayer.rating)
                        .animation(.easeInOut(duration: 0.3), value: highlightHeader)
                    }
                    
                    // --------------------------------------------------------
                    // SPORT PICKER
                    // --------------------------------------------------------
                    VStack(spacing: 8) {
                        Text("Select Sport")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Picker("Sport", selection: $viewModel.selectedSport) {
                            Text("Basketball").tag(Sport.basketball)
                            Text("Football").tag(Sport.football)
                            Text("Soccer").tag(Sport.soccer)
                            Text("Tennis").tag(Sport.tennis)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)
                    
                    // --------------------------------------------------------
                    // SECTION 2: PRIMARY ACTION CARD
                    // --------------------------------------------------------
                    VStack(spacing: 16) {
                        
                        VStack(spacing: 8) {
                            Text("Ready to Compete")
                                .font(.title2.bold())
                            
                            Text("Challenge an opponent and prove your skills")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button {
                            withAnimation {
                                viewModel.simulateMatch()
                                
                                // Trigger highlight flash
                                highlightHeader = true
                                Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    highlightHeader = false
                                }
                            }
                        } label: {
                            Text("Challenge Opponent")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                    .padding(24)
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // --------------------------------------------------------
                    // SECTION 3: RECENT ACTIVITY
                    // --------------------------------------------------------
                    if !viewModel.matchLog.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            
                            Text("Recent Activity")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                ForEach(viewModel.matchLog) { entry in
                                    HStack(spacing: 8) {
                                        Text(entry.winnerName)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.green)
                                        
                                        Text("beat")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        
                                        Text(entry.loserName)
                                            .font(.subheadline)
                                            .foregroundStyle(.red)
                                        
                                        Spacer()
                                        
                                        Text(String(format: "+%.0f", entry.ratingChange))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.green)
                                            .monospacedDigit()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGroupedBackground))
                                    .cornerRadius(8)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Spacer(minLength: 24)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.matchLog.count)
            }
            .navigationTitle("SportsHub")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.startListening()
        }
    }
}

#Preview {
    ContentView()
}
