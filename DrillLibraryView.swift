//
//  DrillLibraryView.swift
//  SportsHub
//
//  Drill library with sport-specific drills
//

import SwiftUI

struct DrillLibraryView: View {
    @Environment(\.dismiss) var dismiss
    
    let sport: Sport
    
    @State private var searchText = ""
    @State private var selectedCategory: TrainingCategory = .all
    @State private var selectedDifficulty: TrainingDifficulty = .all
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filters
                filtersSection
                
                // Drills List
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        ForEach(filteredDrills) { drill in
                            NavigationLink {
                                DrillDetailView(drill: drill)
                            } label: {
                                DrillCard(drill: drill)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(Spacing.md)
                }
            }
            .background(Color.appBackground)
            .navigationTitle("\(sport.rawValue) Drills")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Filters Section
    
    private var filtersSection: some View {
        VStack(spacing: Spacing.sm) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.appTextSecondary)
                
                TextField("Search drills...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
            }
            .padding(Spacing.sm)
            .background(Color.appCardBackground)
            .cornerRadius(10)
            .padding(.horizontal, Spacing.md)
            
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(TrainingCategory.allCases, id: \.self) { category in
                        Button(action: {
                            selectedCategory = category
                        }) {
                            Text(category.rawValue)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(selectedCategory == category ? .white : Color.appTextPrimary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .background(selectedCategory == category ? Color.appPrimary : Color.appCardBackground)
                                .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            
            // Difficulty filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(TrainingDifficulty.allCases, id: \.self) { difficulty in
                        Button(action: {
                            selectedDifficulty = difficulty
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: difficulty.icon)
                                    .font(.caption)
                                Text(difficulty.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(selectedDifficulty == difficulty ? .white : Color.appTextPrimary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(selectedDifficulty == difficulty ? Color.appSecondary : Color.appCardBackground)
                            .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
        .padding(.vertical, Spacing.sm)
        .background(Color.appBackground)
    }
    
    // MARK: - Filtered Drills
    
    private var filteredDrills: [TrainingDrill] {
        var drills = TrainingDrill.drillsForSport(sport)
        
        // Apply category filter
        if selectedCategory != .all {
            drills = drills.filter { $0.category == selectedCategory }
        }
        
        // Apply difficulty filter
        if selectedDifficulty != .all {
            drills = drills.filter { $0.difficulty == selectedDifficulty }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            drills = drills.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return drills
    }
}

// MARK: - Drill Card

struct DrillCard: View {
    let drill: TrainingDrill
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(drill.name)
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    Text(drill.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(Color.appPrimary)
                }
                
                Spacer()
                
                // Difficulty badge
                HStack(spacing: 4) {
                    Image(systemName: drill.difficulty.icon)
                        .font(.caption)
                    Text(drill.difficulty.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(drill.difficulty.color)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background(drill.difficulty.color.opacity(0.1))
                .cornerRadius(8)
            }
            
            Text(drill.description)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .lineLimit(2)
            
            HStack(spacing: Spacing.md) {
                Label("\(drill.duration) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                
                if !drill.equipment.isEmpty {
                    Label(drill.equipment.joined(separator: ", "), systemImage: "gym.bag")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

// MARK: - Supporting Types

enum TrainingCategory: String, CaseIterable {
    case all = "All"
    case fundamentals = "Fundamentals"
    case shooting = "Shooting"
    case passing = "Passing"
    case dribbling = "Dribbling"
    case defense = "Defense"
    case conditioning = "Conditioning"
    case ballControl = "Ball Control"
    case serving = "Serving"
    case throwing = "Throwing"
    case catching = "Catching"
    case footwork = "Footwork"
    case volleys = "Volleys"
}

enum TrainingDifficulty: String, CaseIterable {
    case all = "All Levels"
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    
    var icon: String {
        switch self {
        case .all: return "star"
        case .beginner: return "star.fill"
        case .intermediate: return "star.leadinghalf.filled"
        case .advanced: return "star.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return Color.appTextSecondary
        case .beginner: return .green
        case .intermediate: return Color.appSecondary
        case .advanced: return .red
        }
    }
}

struct TrainingDrill: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let category: TrainingCategory
    let difficulty: TrainingDifficulty
    let duration: Int // minutes
    let equipment: [String]
    let instructions: [String]
    let metrics: [String]
    let tips: [String]
    let sport: Sport
    
    // Sport-specific drill libraries
    static func drillsForSport(_ sport: Sport) -> [TrainingDrill] {
        switch sport {
        case .basketball:
            return basketballDrills
        case .soccer:
            return soccerDrills
        case .tennis:
            return tennisDrills
        case .football:
            return footballDrills
        }
    }
    
    // MARK: - Basketball Drills
    
    static let basketballDrills: [TrainingDrill] = [
        TrainingDrill(
            name: "Form Shooting",
            description: "Perfect your shooting form with close-range repetitions",
            category: .shooting,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Basketball", "Hoop"],
            instructions: [
                "Start 5 feet from the basket",
                "Focus on proper hand position and follow-through",
                "Make 10 shots before moving back",
                "Move back in 2-foot increments",
                "Complete 5 positions total"
            ],
            metrics: ["Makes", "Attempts", "Accuracy %"],
            tips: [
                "Keep your elbow aligned with the basket",
                "Follow through with your wrist",
                "Use your legs for power"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Mikan Drill",
            description: "Develop layup technique and touch around the rim",
            category: .shooting,
            difficulty: .beginner,
            duration: 10,
            equipment: ["Basketball", "Hoop"],
            instructions: [
                "Start under the basket",
                "Alternate layups from each side",
                "Use proper footwork (right-left-shoot for right side)",
                "Focus on soft touch off the backboard",
                "Complete 3 sets of 20 makes"
            ],
            metrics: ["Makes", "Time"],
            tips: [
                "Keep the ball high",
                "Use the backboard",
                "Stay light on your feet"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Cone Dribbling",
            description: "Improve ball handling and change of direction",
            category: .dribbling,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Basketball", "5 Cones"],
            instructions: [
                "Set up 5 cones in a line, 3 feet apart",
                "Dribble through using crossover moves",
                "Complete with both right and left hand",
                "Time yourself and try to beat your record",
                "Do 5 rounds total"
            ],
            metrics: ["Time", "Turnovers"],
            tips: [
                "Stay low in your stance",
                "Keep your head up",
                "Use your off-hand to protect the ball"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Defensive Slides",
            description: "Build lateral quickness and defensive footwork",
            category: .defense,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Court markings"],
            instructions: [
                "Start in defensive stance at baseline",
                "Slide laterally to sideline",
                "Sprint to opposite sideline",
                "Slide back to starting position",
                "Complete 10 repetitions"
            ],
            metrics: ["Reps", "Time per rep"],
            tips: [
                "Never cross your feet",
                "Stay low with knees bent",
                "Keep arms active"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Spot Shooting",
            description: "Build shooting consistency from key spots",
            category: .shooting,
            difficulty: .intermediate,
            duration: 25,
            equipment: ["Basketball", "Hoop"],
            instructions: [
                "Mark 5 spots around the arc",
                "Take 10 shots from each spot",
                "Get your own rebound between shots",
                "Track makes from each position",
                "Rest 2 minutes between rounds"
            ],
            metrics: ["Makes per spot", "Total makes"],
            tips: [
                "Same form every shot",
                "Visualize the make before shooting",
                "Focus on rhythm"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Two-Ball Dribbling",
            description: "Advanced ball handling with both hands simultaneously",
            category: .dribbling,
            difficulty: .advanced,
            duration: 20,
            equipment: ["2 Basketballs"],
            instructions: [
                "Dribble both balls simultaneously",
                "Practice alternating dribbles",
                "Move forward and backward",
                "Try crossovers with both balls",
                "Complete 5-minute intervals"
            ],
            metrics: ["Time", "Control rating"],
            tips: [
                "Start slow and build speed",
                "Keep both balls at same height",
                "Use your peripheral vision"
            ],
            sport: .basketball
        )
    ]
    
    // MARK: - Soccer Drills
    
    static let soccerDrills: [TrainingDrill] = [
        TrainingDrill(
            name: "Juggling",
            description: "Develop first touch and ball control",
            category: .ballControl,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Soccer ball"],
            instructions: [
                "Start by dropping the ball and catching after one bounce",
                "Progress to multiple touches",
                "Use both feet, thighs, and head",
                "Try to beat your record",
                "Do 3 sets"
            ],
            metrics: ["Max touches", "Total touches"],
            tips: [
                "Keep your eyes on the ball",
                "Use gentle touches",
                "Stay relaxed"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "Passing Accuracy",
            description: "Improve short and long passing technique",
            category: .passing,
            difficulty: .beginner,
            duration: 20,
            equipment: ["Soccer ball", "Target cones", "Partner optional"],
            instructions: [
                "Set up targets 10, 20, and 30 yards away",
                "Pass to hit each target 10 times",
                "Use both inside and outside of foot",
                "Track accuracy for each distance",
                "With partner: complete 50 passes without miss"
            ],
            metrics: ["Accuracy %", "Successful passes"],
            tips: [
                "Plant foot beside the ball",
                "Follow through toward target",
                "Keep ankle locked"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "Cone Weaving",
            description: "Master close control and dribbling through traffic",
            category: .dribbling,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Soccer ball", "8 Cones"],
            instructions: [
                "Set up 8 cones in a line, 2 feet apart",
                "Dribble through using various moves",
                "Practice with inside and outside of both feet",
                "Time yourself",
                "Complete 10 runs"
            ],
            metrics: ["Time", "Touches", "Clean runs"],
            tips: [
                "Keep the ball close",
                "Change pace",
                "Look up between cones"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "Shooting Accuracy",
            description: "Practice finishing from various positions",
            category: .shooting,
            difficulty: .intermediate,
            duration: 25,
            equipment: ["Soccer ball", "Goal", "Target markers"],
            instructions: [
                "Mark target zones in corners of goal",
                "Take 10 shots from each marked position",
                "Aim for specific target zones",
                "Track accuracy and power",
                "Include both feet"
            ],
            metrics: ["Goals", "On target", "Accuracy %"],
            tips: [
                "Plant foot beside the ball",
                "Strike through the center",
                "Follow through toward goal"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "1v1 Defense",
            description: "Improve defensive positioning and timing",
            category: .defense,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Soccer ball", "Partner", "Small goal"],
            instructions: [
                "Set up small goals or cones",
                "Partner attacks, you defend",
                "Focus on staying between ball and goal",
                "Switch roles after 10 attempts",
                "Track successful stops"
            ],
            metrics: ["Stops", "Goals conceded"],
            tips: [
                "Stay on your toes",
                "Don't dive in",
                "Force to weaker side"
            ],
            sport: .soccer
        )
    ]
    
    // MARK: - Tennis Drills
    
    static let tennisDrills: [TrainingDrill] = [
        TrainingDrill(
            name: "Serve Practice",
            description: "Develop consistent and powerful serves",
            category: .serving,
            difficulty: .beginner,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Court"],
            instructions: [
                "Hit 20 serves to deuce court",
                "Hit 20 serves to ad court",
                "Focus on toss consistency",
                "Practice both flat and spin serves",
                "Track first serve percentage"
            ],
            metrics: ["In serves", "First serve %", "Aces"],
            tips: [
                "Toss the ball in front of you",
                "Use full shoulder rotation",
                "Snap your wrist on contact"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Baseline Rallying",
            description: "Build consistency and footwork from baseline",
            category: .fundamentals,
            difficulty: .intermediate,
            duration: 30,
            equipment: ["Tennis balls", "Racket", "Partner", "Court"],
            instructions: [
                "Rally with partner from baseline",
                "Try to keep ball in play for 20+ shots",
                "Focus on consistent depth and placement",
                "Mix in topspin and slice",
                "Do 10-minute intervals"
            ],
            metrics: ["Rally length", "Unforced errors"],
            tips: [
                "Split step before each shot",
                "Stay balanced",
                "Aim 3-5 feet inside baseline"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Volley Wall",
            description: "Practice volleys and reaction time",
            category: .volleys,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Tennis balls", "Racket", "Wall or backboard"],
            instructions: [
                "Stand 10 feet from wall",
                "Hit continuous volleys",
                "Try to sustain for 1 minute",
                "Practice forehand and backhand",
                "Do 5 rounds"
            ],
            metrics: ["Max consecutive volleys", "Time"],
            tips: [
                "Keep racket in front",
                "Use short compact swings",
                "Stay on your toes"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Approach Shots",
            description: "Master transitioning from baseline to net",
            category: .fundamentals,
            difficulty: .advanced,
            duration: 25,
            equipment: ["Tennis balls", "Racket", "Partner", "Court"],
            instructions: [
                "Partner feeds short balls",
                "Hit approach shot deep",
                "Move forward to net",
                "Finish with volley or overhead",
                "Practice 20 repetitions each side"
            ],
            metrics: ["Successful approaches", "Point wins"],
            tips: [
                "Hit deep to corners",
                "Move forward immediately",
                "Stay aggressive at net"
            ],
            sport: .tennis
        )
    ]
    
    // MARK: - Football Drills
    
    static let footballDrills: [TrainingDrill] = [
        TrainingDrill(
            name: "Throwing Mechanics",
            description: "Perfect your QB throwing motion and accuracy",
            category: .throwing,
            difficulty: .beginner,
            duration: 20,
            equipment: ["Football", "Target net or partner"],
            instructions: [
                "Focus on proper grip and release",
                "Start with short 10-yard throws",
                "Progress to medium 20-yard routes",
                "Practice deep balls 30+ yards",
                "Complete 50 total throws"
            ],
            metrics: ["Completions", "Accuracy %", "Distance"],
            tips: [
                "Step into your throw",
                "Follow through to target",
                "Keep elbow high"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Route Running",
            description: "Sharp cuts and precise route execution",
            category: .fundamentals,
            difficulty: .intermediate,
            duration: 25,
            equipment: ["Cones", "Football", "Partner QB"],
            instructions: [
                "Practice 5 basic routes: slant, out, curl, post, go",
                "Focus on sharp cuts at break points",
                "Track with eyes before catch",
                "Run each route 5 times",
                "Full speed every rep"
            ],
            metrics: ["Catches", "Drop rate", "Separation"],
            tips: [
                "Sell the route with eyes",
                "Plant and drive at breaks",
                "Secure the catch first"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Cone Agility",
            description: "Improve footwork and change of direction",
            category: .footwork,
            difficulty: .beginner,
            duration: 15,
            equipment: ["5 Cones"],
            instructions: [
                "Set up 5-cone drill pattern",
                "Run through focusing on quick feet",
                "Time each run",
                "Complete 10 repetitions",
                "Rest 45 seconds between reps"
            ],
            metrics: ["Time", "Best time"],
            tips: [
                "Stay low through cuts",
                "Push off outside foot",
                "Keep shoulders square"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Ball Security",
            description: "Practice carrying and protecting the football",
            category: .fundamentals,
            difficulty: .beginner,
            duration: 20,
            equipment: ["Football"],
            instructions: [
                "Practice high-and-tight carry position",
                "Run through cone course",
                "Have partner attempt strips",
                "Switch carrying arm throughout",
                "Complete 15 runs"
            ],
            metrics: ["Fumbles", "Successful strips avoided"],
            tips: [
                "Five points of pressure",
                "Cover ball in traffic",
                "Switch arms away from defenders"
            ],
            sport: .football
        )
    ]
    
    // Volleyball and Baseball drills removed - sports not currently supported
}

#Preview {
    DrillLibraryView(sport: .basketball)
}
