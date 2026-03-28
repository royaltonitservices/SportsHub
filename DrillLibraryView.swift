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
                    ForEach(TrainingCategory.categoriesFor(sport: sport), id: \.self) { category in
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

// Sport-specific category system
enum TrainingCategory: String, Hashable {
    // Universal
    case all = "All"
    
    // Basketball-specific
    case ballHandling = "Ball Handling"
    case basketballShooting = "Shooting"
    case finishing = "Finishing"
    case basketballPassing = "Passing"
    case basketballDefense = "Defense"
    case basketballFootwork = "Footwork"
    case basketballConditioning = "Conditioning"
    case basketballIQ = "IQ & Decision Making"
    case oneOnOneMoves = "1v1 Moves"
    case rebounding = "Rebounding"
    case agility = "Agility"
    
    // Football-specific
    case footballPassing = "Passing (QB)"
    case footballCatching = "Catching"
    case routeRunning = "Route Running"
    case footballFootwork = "Footwork (FB)"
    case speedAgility = "Speed & Agility"
    case throwingMechanics = "Throwing Mechanics"
    case qbDrills = "QB Drills"
    case wrDrills = "WR Drills"
    case rbDrills = "RB Drills"
    case dbDrills = "DB Drills"
    case footballConditioning = "Conditioning (FB)"
    case reaction = "Reaction (FB)"
    
    // Soccer-specific
    case soccerDribbling = "Dribbling"
    case soccerPassing = "Passing (Soccer)"
    case soccerShooting = "Shooting (Soccer)"
    case firstTouch = "First Touch"
    case soccerFinishing = "Finishing (Soccer)"
    case ballControl = "Ball Control"
    case soccerFootwork = "Footwork (Soccer)"
    case soccerDefense = "Defense (Soccer)"
    case soccerConditioning = "Conditioning (Soccer)"
    case weakFoot = "Weak Foot"
    case positionSpecific = "Position-Specific"
    
    // Tennis-specific
    case forehand = "Forehand"
    case backhand = "Backhand"
    case serve = "Serve"
    case returnOfServe = "Return of Serve"
    case tennisFootwork = "Footwork (Tennis)"
    case volley = "Volley"
    case consistency = "Consistency"
    case movement = "Movement"
    case tennisConditioning = "Conditioning (Tennis)"
    case matchPrep = "Match Prep"
    case accuracy = "Accuracy"
    case tennisReaction = "Reaction (Tennis)"
    
    // Get categories for specific sport
    static func categoriesFor(sport: Sport) -> [TrainingCategory] {
        switch sport {
        case .basketball:
            return [.all, .ballHandling, .basketballShooting, .finishing, .basketballPassing, .basketballDefense, .basketballFootwork, .basketballConditioning, .basketballIQ, .oneOnOneMoves, .rebounding, .agility]
        case .football:
            return [.all, .footballPassing, .footballCatching, .routeRunning, .footballFootwork, .speedAgility, .throwingMechanics, .qbDrills, .wrDrills, .rbDrills, .dbDrills, .footballConditioning, .reaction]
        case .soccer:
            return [.all, .soccerDribbling, .soccerPassing, .soccerShooting, .firstTouch, .soccerFinishing, .ballControl, .soccerFootwork, .soccerDefense, .soccerConditioning, .weakFoot, .positionSpecific]
        case .tennis:
            return [.all, .forehand, .backhand, .serve, .returnOfServe, .tennisFootwork, .volley, .consistency, .movement, .tennisConditioning, .matchPrep, .accuracy, .tennisReaction]
        }
    }
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
        // Ball Handling
        TrainingDrill(
            name: "Stationary Ball Handling",
            description: "Master fundamental ball control moves in place",
            category: .ballHandling,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Basketball"],
            instructions: [
                "Perform figure-8s through legs for 30 seconds",
                "Do around-the-waist circles both directions",
                "Practice between-legs dribbles",
                "Perform around-the-head circles",
                "Complete 3 full rounds"
            ],
            metrics: ["Clean reps", "Time", "Drops"],
            tips: [
                "Keep movements tight and controlled",
                "Look straight ahead, not at ball",
                "Gradually increase speed"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Two-Ball Dribbling",
            description: "Advanced ball handling with both hands simultaneously",
            category: .ballHandling,
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
        ),
        TrainingDrill(
            name: "Cone Dribbling",
            description: "Improve ball handling and change of direction",
            category: .ballHandling,
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
            name: "Spider Dribble",
            description: "Build hand quickness and coordination through legs",
            category: .ballHandling,
            difficulty: .intermediate,
            duration: 12,
            equipment: ["Basketball"],
            instructions: [
                "Spread legs shoulder-width apart",
                "Dribble ball between and around legs in continuous motion",
                "Right hand front, left hand back pattern",
                "30 seconds forward, 30 seconds backward",
                "Complete 4 sets"
            ],
            metrics: ["Reps", "Clean sets"],
            tips: [
                "Keep dribbles low and quick",
                "Maintain rhythm throughout",
                "Don't look down at the ball"
            ],
            sport: .basketball
        ),
        
        // Shooting
        TrainingDrill(
            name: "Form Shooting",
            description: "Master shooting mechanics from close range",
            category: .basketballShooting,
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
            name: "Spot Shooting",
            description: "Build shooting consistency from key spots",
            category: .basketballShooting,
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
            name: "Free Throw Routine",
            description: "Develop consistency from the charity stripe",
            category: .basketballShooting,
            difficulty: .beginner,
            duration: 20,
            equipment: ["Basketball", "Hoop"],
            instructions: [
                "Establish your pre-shot routine",
                "Shoot 10 free throws, count makes",
                "Rest 1 minute between sets",
                "Complete 5 sets of 10",
                "Track percentage for each set"
            ],
            metrics: ["Makes", "Percentage", "Consecutive makes"],
            tips: [
                "Use same routine every time",
                "Take a deep breath before shooting",
                "Focus on the back of the rim"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Catch and Shoot",
            description: "Practice shooting off the pass in game situations",
            category: .basketballShooting,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Basketball", "Hoop", "Partner or machine"],
            instructions: [
                "Start at various spots around the arc",
                "Partner passes, you catch and shoot immediately",
                "Focus on quick footwork and release",
                "Take 10 shots from each spot",
                "Track makes from each position"
            ],
            metrics: ["Makes", "Release time", "Accuracy %"],
            tips: [
                "Get feet ready before the catch",
                "Catch in shooting pocket",
                "Minimize time between catch and release"
            ],
            sport: .basketball
        ),
        
        // Finishing
        TrainingDrill(
            name: "Mikan Drill",
            description: "Develop layup technique and touch around the rim",
            category: .finishing,
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
            name: "Euro Step Finishes",
            description: "Master the euro step to avoid defenders at the rim",
            category: .finishing,
            difficulty: .advanced,
            duration: 15,
            equipment: ["Basketball", "Hoop", "2 Cones"],
            instructions: [
                "Set up cones as defenders near the paint",
                "Attack from various angles",
                "Execute euro step around cones",
                "Finish with both hands",
                "Complete 20 reps total"
            ],
            metrics: ["Makes", "Successful euro steps"],
            tips: [
                "Take wide steps to create space",
                "Keep ball protected during step",
                "Explode up after second step"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Reverse Layup Series",
            description: "Practice finishing on the opposite side of the rim",
            category: .finishing,
            difficulty: .intermediate,
            duration: 15,
            equipment: ["Basketball", "Hoop"],
            instructions: [
                "Attack from both wings",
                "Go under the basket to opposite side",
                "Use backboard for soft finish",
                "Practice with both hands",
                "Make 15 from each side"
            ],
            metrics: ["Makes per side", "Total makes"],
            tips: [
                "Protect ball with body",
                "Use high arc over the rim",
                "Soft touch on the glass"
            ],
            sport: .basketball
        ),
        
        // Passing
        TrainingDrill(
            name: "Wall Passing",
            description: "Build passing strength and accuracy",
            category: .basketballPassing,
            difficulty: .beginner,
            duration: 12,
            equipment: ["Basketball", "Wall"],
            instructions: [
                "Stand 10 feet from wall",
                "Perform chest passes for 30 seconds",
                "Perform bounce passes for 30 seconds",
                "Perform overhead passes for 30 seconds",
                "Complete 3 rounds"
            ],
            metrics: ["Clean catches", "Time"],
            tips: [
                "Step into each pass",
                "Aim for same spot on wall",
                "Quick hands on the catch"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Partner Passing Series",
            description: "Practice various passes with a teammate",
            category: .basketballPassing,
            difficulty: .intermediate,
            duration: 15,
            equipment: ["Basketball", "Partner"],
            instructions: [
                "Chest pass: 20 reps",
                "Bounce pass: 20 reps",
                "Overhead pass: 20 reps",
                "Behind-the-back: 10 reps each hand",
                "No-look passes: 10 reps"
            ],
            metrics: ["Completions", "Drops"],
            tips: [
                "Communicate with partner",
                "Pass away from defense",
                "Lead your partner into space"
            ],
            sport: .basketball
        ),
        
        // Defense
        TrainingDrill(
            name: "Defensive Slides",
            description: "Build lateral quickness and defensive footwork",
            category: .basketballDefense,
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
            name: "Closeout Drill",
            description: "Practice closing out on shooters efficiently",
            category: .basketballDefense,
            difficulty: .intermediate,
            duration: 12,
            equipment: ["Basketball", "Partner or cone"],
            instructions: [
                "Start at free throw line",
                "Sprint to close out on shooter at 3-point line",
                "Arrive in controlled defensive stance",
                "Shuffle to contest shot",
                "Complete 15 closeouts"
            ],
            metrics: ["Quality closeouts", "Time"],
            tips: [
                "Sprint early, chop feet late",
                "Hand up to contest",
                "Don't fly by the shooter"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Shell Drill",
            description: "Master team defensive rotations",
            category: .basketballDefense,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Basketball", "4 players"],
            instructions: [
                "4-on-4 defensive positioning drill",
                "Defense moves with ball movement",
                "Practice help-side positioning",
                "Communicate rotations verbally",
                "Go for 2-minute intervals"
            ],
            metrics: ["Successful stops", "Communication"],
            tips: [
                "Stay in your stance",
                "See ball and man",
                "Talk on every pass"
            ],
            sport: .basketball
        ),
        
        // Footwork
        TrainingDrill(
            name: "Ladder Drills",
            description: "Improve foot speed and coordination",
            category: .basketballFootwork,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Agility ladder"],
            instructions: [
                "One foot in each square: 3 rounds",
                "Two feet in each square: 3 rounds",
                "Lateral shuffle through: 3 rounds",
                "Icky shuffle: 3 rounds",
                "Rest 30 seconds between rounds"
            ],
            metrics: ["Clean runs", "Time"],
            tips: [
                "Stay on balls of feet",
                "Keep head up",
                "Move quickly but controlled"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Pivoting Fundamentals",
            description: "Master pivoting to protect the ball",
            category: .basketballFootwork,
            difficulty: .beginner,
            duration: 10,
            equipment: ["Basketball"],
            instructions: [
                "Practice forward pivot 10 times each foot",
                "Practice reverse pivot 10 times each foot",
                "Combine with triple threat position",
                "Add defender pressure",
                "Complete 3 sets"
            ],
            metrics: ["Clean pivots", "Travel violations"],
            tips: [
                "Keep pivot foot planted",
                "Protect ball with body",
                "Stay balanced and low"
            ],
            sport: .basketball
        ),
        
        // Conditioning
        TrainingDrill(
            name: "Suicide Sprints",
            description: "Build endurance and speed",
            category: .basketballConditioning,
            difficulty: .intermediate,
            duration: 15,
            equipment: ["Court markings"],
            instructions: [
                "Sprint to free throw line and back",
                "Sprint to half court and back",
                "Sprint to opposite free throw line and back",
                "Sprint to opposite baseline and back",
                "Complete 5 full suicides"
            ],
            metrics: ["Time per suicide", "Best time"],
            tips: [
                "Touch each line",
                "Maintain form when tired",
                "Push through the burn"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "17s Conditioning",
            description: "Game-speed conditioning drill",
            category: .basketballConditioning,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Court", "Timer"],
            instructions: [
                "Sprint baseline to baseline and back",
                "Complete in under 17 seconds",
                "Rest until minute mark",
                "Repeat for 10-12 total runs",
                "Must make all 10 under 17 seconds"
            ],
            metrics: ["Successful runs", "Times"],
            tips: [
                "Pace yourself early",
                "Stay mentally tough",
                "Touch each baseline"
            ],
            sport: .basketball
        ),
        
        // 1v1 Moves
        TrainingDrill(
            name: "Crossover Series",
            description: "Master the crossover and its variations",
            category: .oneOnOneMoves,
            difficulty: .intermediate,
            duration: 15,
            equipment: ["Basketball", "Cone"],
            instructions: [
                "Standard crossover: 10 reps each direction",
                "Between-legs crossover: 10 reps",
                "Behind-back crossover: 10 reps",
                "Double crossover: 10 reps",
                "Finish with layup or pull-up"
            ],
            metrics: ["Clean moves", "Finishes"],
            tips: [
                "Sell the first move",
                "Keep dribble low on cross",
                "Explode after the move"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Hesitation Move",
            description: "Freeze defenders with change of pace",
            category: .oneOnOneMoves,
            difficulty: .advanced,
            duration: 12,
            equipment: ["Basketball", "Cone"],
            instructions: [
                "Attack cone at 75% speed",
                "Plant foot and pause with ball",
                "Read defender reaction",
                "Explode past cone",
                "Complete 15 reps"
            ],
            metrics: ["Successful freezes", "Finishes"],
            tips: [
                "Sell the hesitation with body",
                "Keep defender off balance",
                "Accelerate explosively"
            ],
            sport: .basketball
        ),
        
        // Rebounding
        TrainingDrill(
            name: "Box Out Fundamentals",
            description: "Learn proper rebounding positioning",
            category: .rebounding,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Basketball", "Hoop", "Partner"],
            instructions: [
                "Partner shoots, you find and box out",
                "Make contact with partner's body",
                "Maintain position until ball bounces",
                "Secure rebound with both hands",
                "Complete 20 reps"
            ],
            metrics: ["Rebounds secured", "Box outs"],
            tips: [
                "Find your man first",
                "Make and keep contact",
                "Go get the ball aggressively"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Tip Drill",
            description: "Improve offensive rebounding and tip timing",
            category: .rebounding,
            difficulty: .intermediate,
            duration: 10,
            equipment: ["Basketball", "Hoop"],
            instructions: [
                "Toss ball off backboard",
                "Jump and tip back up without catching",
                "Keep tipping until it goes in",
                "Alternate right and left hands",
                "Complete 15 makes"
            ],
            metrics: ["Makes", "Tips per make"],
            tips: [
                "Time your jump",
                "Extend fully at the rim",
                "Use fingertips not palm"
            ],
            sport: .basketball
        ),
        
        // IQ & Decision Making
        TrainingDrill(
            name: "3-on-2, 2-on-1 Break",
            description: "Practice fast break decision making",
            category: .basketballIQ,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Basketball", "Hoop", "5 players"],
            instructions: [
                "3 offensive players attack 2 defenders",
                "Score or stop, then 2 defenders attack other way",
                "1 offensive player hustles back on defense",
                "Continuous drill for 5 minutes",
                "Track conversions and stops"
            ],
            metrics: ["Conversions", "Stops", "Good decisions"],
            tips: [
                "Attack quickly but under control",
                "Make the extra pass",
                "Don't force bad shots"
            ],
            sport: .basketball
        ),
        TrainingDrill(
            name: "Triple Threat Reads",
            description: "Learn to read defenders from triple threat",
            category: .basketballIQ,
            difficulty: .intermediate,
            duration: 15,
            equipment: ["Basketball", "Hoop", "Partner defender"],
            instructions: [
                "Catch ball in triple threat position",
                "Read how defender guards you",
                "If they're high, drive past",
                "If they're low, shoot",
                "If balanced, make a move",
                "Complete 20 reps"
            ],
            metrics: ["Correct reads", "Scores"],
            tips: [
                "Survey defense before moving",
                "Be a threat in all three ways",
                "Attack the defender's weakness"
            ],
            sport: .basketball
        )
    ]
    
    // MARK: - Soccer Drills
    
    static let soccerDrills: [TrainingDrill] = [
        // Dribbling
        TrainingDrill(
            name: "Cone Weaving",
            description: "Master close control and dribbling through traffic",
            category: .soccerDribbling,
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
            name: "1v1 Dribbling Moves",
            description: "Learn effective moves to beat defenders",
            category: .soccerDribbling,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Soccer ball", "Cone or partner"],
            instructions: [
                "Practice stepover: 10 reps each foot",
                "Practice scissors: 10 reps each direction",
                "Practice Cruyff turn: 10 reps each foot",
                "Practice drag-back: 10 reps",
                "Finish each move with acceleration"
            ],
            metrics: ["Clean executions", "Beat rate"],
            tips: [
                "Sell the fake with your body",
                "Keep ball close during move",
                "Explode after the touch"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "Speed Dribbling",
            description: "Develop ability to dribble at pace",
            category: .soccerDribbling,
            difficulty: .advanced,
            duration: 15,
            equipment: ["Soccer ball", "40-yard space"],
            instructions: [
                "Dribble 40 yards at maximum speed",
                "Keep ball under control",
                "Use laces to push ball forward",
                "Complete 8 sprints",
                "Track time for each"
            ],
            metrics: ["Times", "Control rating"],
            tips: [
                "Push ball 3-4 yards ahead",
                "Sprint after your touches",
                "Don't slow down for touches"
            ],
            sport: .soccer
        ),
        
        // Passing
        TrainingDrill(
            name: "Passing Accuracy",
            description: "Improve short and long passing technique",
            category: .soccerPassing,
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
            name: "Wall Passing (One-Two)",
            description: "Master give-and-go combinations",
            category: .soccerPassing,
            difficulty: .intermediate,
            duration: 15,
            equipment: ["Soccer ball", "Wall or partner", "Cones"],
            instructions: [
                "Pass to wall, receive on the move",
                "Take 1-2 touches maximum",
                "Vary angles and distances",
                "Practice both feet",
                "Complete 50 combinations"
            ],
            metrics: ["Clean combinations", "First touch quality"],
            tips: [
                "Pass into space for yourself",
                "Move immediately after passing",
                "Use proper weight on return"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "Through Ball Accuracy",
            description: "Learn to play splitting passes",
            category: .soccerPassing,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Soccer ball", "Cones", "Partner"],
            instructions: [
                "Set up cones as defenders",
                "Play through balls between cones",
                "Partner runs onto passes",
                "Practice with inside and outside of foot",
                "Complete 20 successful through balls"
            ],
            metrics: ["Successful splits", "Weight of pass"],
            tips: [
                "Disguise your intention",
                "Weight pass for runner's speed",
                "Hit the space, not the player"
            ],
            sport: .soccer
        ),
        
        // Shooting
        TrainingDrill(
            name: "Shooting Accuracy",
            description: "Practice finishing from various positions",
            category: .soccerShooting,
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
            name: "Volleys and Half-Volleys",
            description: "Master striking balls out of the air",
            category: .soccerShooting,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Soccer ball", "Goal", "Partner"],
            instructions: [
                "Partner tosses or crosses balls",
                "Strike on the volley (before bounce)",
                "Strike on half-volley (just after bounce)",
                "Focus on technique over power initially",
                "Complete 30 attempts"
            ],
            metrics: ["On target", "Goals", "Clean strikes"],
            tips: [
                "Keep eye on the ball",
                "Strike through center of ball",
                "Keep body over the ball"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "Finesse Finishing",
            description: "Learn to place shots with accuracy",
            category: .soccerShooting,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Soccer ball", "Goal", "Cones"],
            instructions: [
                "Place cones in far corners of goal",
                "Use inside of foot for placement",
                "Focus on accuracy over power",
                "Shoot from various angles",
                "Complete 25 finesse shots"
            ],
            metrics: ["Goals in target zones", "Accuracy %"],
            tips: [
                "Open up your body",
                "Use inside of foot",
                "Follow through across your body"
            ],
            sport: .soccer
        ),
        
        // First Touch
        TrainingDrill(
            name: "Juggling",
            description: "Develop first touch and ball control",
            category: .firstTouch,
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
            name: "First Touch Directional Control",
            description: "Control passes and direct them into space",
            category: .firstTouch,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Soccer ball", "Partner", "Cones for targets"],
            instructions: [
                "Partner passes from different angles",
                "Control ball toward specific target cone",
                "Use various surfaces: inside, outside, sole",
                "Take ball in one touch to target",
                "Complete 40 touches"
            ],
            metrics: ["Successful directional touches", "Touch quality"],
            tips: [
                "Cushion the ball on contact",
                "Set yourself for next action",
                "Use appropriate surface for direction"
            ],
            sport: .soccer
        ),
        
        // Ball Control
        TrainingDrill(
            name: "Close Control Square",
            description: "Master tight spaces ball manipulation",
            category: .ballControl,
            difficulty: .intermediate,
            duration: 15,
            equipment: ["Soccer ball", "4 Cones (5x5 yard square)"],
            instructions: [
                "Stay within the small square",
                "Practice various touches and turns",
                "Use all surfaces of both feet",
                "Change direction frequently",
                "Complete 5 minutes of work"
            ],
            metrics: ["Touches in space", "Control rating"],
            tips: [
                "Keep ball very close",
                "Head up to scan space",
                "Be creative with touches"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "Ball Mastery Routine",
            description: "Build fundamental ball familiarity",
            category: .ballControl,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Soccer ball"],
            instructions: [
                "Sole rolls: 30 seconds each foot",
                "Inside-outside taps: 30 seconds each foot",
                "Pull-backs: 20 reps each foot",
                "Foundation touches: 1 minute",
                "Complete 3 full rounds"
            ],
            metrics: ["Clean touches", "Time"],
            tips: [
                "Stay light on your feet",
                "Maintain rhythm",
                "Quality over speed initially"
            ],
            sport: .soccer
        ),
        
        // Footwork
        TrainingDrill(
            name: "Ladder Footwork",
            description: "Improve foot speed and coordination",
            category: .soccerFootwork,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Agility ladder"],
            instructions: [
                "One foot in each square: 3 rounds",
                "Two feet in each square: 3 rounds",
                "Lateral shuffle: 3 rounds",
                "Icky shuffle: 3 rounds",
                "Rest 30 seconds between"
            ],
            metrics: ["Clean runs", "Time"],
            tips: [
                "Stay on balls of feet",
                "Quick, light touches",
                "Keep head up"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "Cutting and Turning",
            description: "Master quick changes of direction",
            category: .soccerFootwork,
            difficulty: .intermediate,
            duration: 15,
            equipment: ["Soccer ball", "Cones"],
            instructions: [
                "Set up cones in pattern",
                "Practice inside cut: 10 reps each foot",
                "Practice outside cut: 10 reps each foot",
                "Practice Cruyff turn: 10 reps each foot",
                "Add ball and go full speed"
            ],
            metrics: ["Clean cuts", "Speed of execution"],
            tips: [
                "Plant and explode",
                "Drop your hips",
                "Accelerate out of the turn"
            ],
            sport: .soccer
        ),
        
        // Defense
        TrainingDrill(
            name: "1v1 Defending",
            description: "Improve defensive positioning and timing",
            category: .soccerDefense,
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
        ),
        TrainingDrill(
            name: "Jockeying Technique",
            description: "Learn to delay attackers and contain",
            category: .soccerDefense,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Cones", "Partner with ball"],
            instructions: [
                "Partner dribbles toward you",
                "Backpedal and jockey without committing",
                "Stay between attacker and goal",
                "Force attacker wide",
                "Complete 15 reps"
            ],
            metrics: ["Successful delays", "Times beaten"],
            tips: [
                "Stay low and balanced",
                "Show them to one side",
                "Be patient, don't lunge"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "Pressing and Tackling",
            description: "Learn when and how to win the ball",
            category: .soccerDefense,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Soccer ball", "Partner", "Cones"],
            instructions: [
                "Identify trigger to press (heavy touch)",
                "Close space quickly",
                "Execute clean tackle",
                "Win ball or force error",
                "Complete 20 press attempts"
            ],
            metrics: ["Balls won", "Fouls", "Success rate"],
            tips: [
                "Press on poor touches",
                "Accelerate to close space",
                "Stay on your feet for tackle"
            ],
            sport: .soccer
        ),
        
        // Conditioning
        TrainingDrill(
            name: "Interval Running",
            description: "Build soccer-specific endurance",
            category: .soccerConditioning,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Field or track"],
            instructions: [
                "Sprint 40 yards at max effort",
                "Jog back for recovery",
                "Repeat for 15 rounds",
                "Rest 3 minutes between sets",
                "Complete 2-3 sets"
            ],
            metrics: ["Sprint times", "Recovery heart rate"],
            tips: [
                "Give full effort on sprints",
                "Use jog for active recovery",
                "This mimics game demands"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "Beep Test (Yo-Yo)",
            description: "Test and build aerobic capacity",
            category: .soccerConditioning,
            difficulty: .advanced,
            duration: 25,
            equipment: ["20-meter course", "Beep test audio"],
            instructions: [
                "Run 20 meters in time with beeps",
                "Turn and run back before next beep",
                "Speed increases every minute",
                "Keep going until you can't maintain pace",
                "Track your level achieved"
            ],
            metrics: ["Level reached", "Total shuttles"],
            tips: [
                "Pace yourself early levels",
                "Turn efficiently",
                "Mental toughness is everything"
            ],
            sport: .soccer
        ),
        
        // Weak Foot
        TrainingDrill(
            name: "Weak Foot Passing",
            description: "Develop comfort with weaker foot",
            category: .weakFoot,
            difficulty: .beginner,
            duration: 20,
            equipment: ["Soccer ball", "Wall or partner"],
            instructions: [
                "Pass ONLY with weak foot",
                "Start at 5 yards, gradually increase distance",
                "Focus on proper technique",
                "Complete 100 passes",
                "Track accuracy"
            ],
            metrics: ["Accuracy %", "Clean strikes"],
            tips: [
                "Use same form as strong foot",
                "Don't rush the process",
                "Quality over quantity"
            ],
            sport: .soccer
        ),
        TrainingDrill(
            name: "Weak Foot Shooting",
            description: "Build confidence finishing with weak foot",
            category: .weakFoot,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Soccer ball", "Goal"],
            instructions: [
                "Take ALL shots with weak foot only",
                "Start close, progress to distance",
                "Shoot from various angles",
                "Track makes vs attempts",
                "Complete 50 shots"
            ],
            metrics: ["Goals", "On target %", "Technique rating"],
            tips: [
                "Focus on contact point",
                "Follow through completely",
                "Celebrate weak foot goals!"
            ],
            sport: .soccer
        )
    ]
    
    // MARK: - Tennis Drills
    
    static let tennisDrills: [TrainingDrill] = [
        // Forehand
        TrainingDrill(
            name: "Forehand Consistency",
            description: "Build reliable forehand mechanics",
            category: .forehand,
            difficulty: .beginner,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Wall or partner"],
            instructions: [
                "Hit 100 forehands focusing on form",
                "Aim for consistent depth",
                "Track unforced errors",
                "Practice topspin and flat shots",
                "Complete 3 sets"
            ],
            metrics: ["Unforced errors", "Depth consistency"],
            tips: [
                "Turn shoulders early",
                "Swing low to high for topspin",
                "Follow through over opposite shoulder"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Forehand Targets",
            description: "Improve forehand placement and accuracy",
            category: .forehand,
            difficulty: .intermediate,
            duration: 25,
            equipment: ["Tennis balls", "Racket", "Court", "Target cones"],
            instructions: [
                "Place targets in corners and short court",
                "Hit 10 forehands to each target",
                "Practice inside-out and inside-in",
                "Track accuracy percentage",
                "Increase difficulty with movement"
            ],
            metrics: ["Target hits", "Accuracy %", "Winners"],
            tips: [
                "Use unit turn for preparation",
                "Adjust grip for spin variation",
                "Recover to ready position quickly"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Running Forehand",
            description: "Hit forehands on the move",
            category: .forehand,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Court", "Partner or ball machine"],
            instructions: [
                "Partner feeds wide to forehand side",
                "Run and hit aggressive forehand",
                "Recover back to center",
                "Complete 30 running forehands",
                "Focus on balance and timing"
            ],
            metrics: ["Winners", "Errors", "Recovery time"],
            tips: [
                "Set up early despite running",
                "Stay balanced on contact",
                "Use open stance when stretched"
            ],
            sport: .tennis
        ),
        
        // Backhand
        TrainingDrill(
            name: "Backhand Mechanics",
            description: "Master backhand technique (1H or 2H)",
            category: .backhand,
            difficulty: .beginner,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Wall or partner"],
            instructions: [
                "Hit 100 backhands with proper form",
                "Focus on shoulder turn and follow-through",
                "Practice both crosscourt and down the line",
                "Track clean hits vs errors",
                "Work on topspin consistency"
            ],
            metrics: ["Clean strikes", "Unforced errors", "Depth"],
            tips: [
                "Turn shoulders completely",
                "Contact ball in front",
                "Extend through the shot"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Backhand Slice",
            description: "Develop effective slice backhand",
            category: .backhand,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Partner"],
            instructions: [
                "Practice slice technique with high-to-low swing",
                "Hit 50 slice backhands",
                "Focus on keeping ball low",
                "Mix in slice approach shots",
                "Track depth and consistency"
            ],
            metrics: ["Depth consistency", "Low clearance %"],
            tips: [
                "Use continental grip",
                "Brush down back of ball",
                "Keep wrist firm"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Down the Line Backhand",
            description: "Master backhand down the line shot",
            category: .backhand,
            difficulty: .advanced,
            duration: 25,
            equipment: ["Tennis balls", "Racket", "Partner", "Court"],
            instructions: [
                "Partner feeds crosscourt to backhand",
                "Hit down the line for winners",
                "Focus on taking ball early",
                "Practice disguising direction",
                "Complete 40 attempts"
            ],
            metrics: ["Winners", "Errors", "Success rate"],
            tips: [
                "Take ball on the rise",
                "Open up stance slightly",
                "Drive through the shot"
            ],
            sport: .tennis
        ),
        
        // Serve
        TrainingDrill(
            name: "Serve Fundamentals",
            description: "Develop consistent and powerful serves",
            category: .serve,
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
            name: "Serve Placement",
            description: "Master serving to all three boxes",
            category: .serve,
            difficulty: .intermediate,
            duration: 25,
            equipment: ["Tennis balls", "Racket", "Court", "Target markers"],
            instructions: [
                "Practice wide serve to deuce and ad",
                "Practice body serve (T)",
                "Practice down the middle",
                "Hit 10 serves to each target",
                "Track accuracy by location"
            ],
            metrics: ["Accuracy by zone", "First serve %"],
            tips: [
                "Adjust toss for each serve direction",
                "Use spin for wide serves",
                "Power down the T"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Second Serve Development",
            description: "Build reliable kick and slice second serves",
            category: .serve,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Court"],
            instructions: [
                "Practice kick serve with topspin",
                "Practice slice serve with sidespin",
                "Focus on high percentage (80%+)",
                "Serve under pressure scenarios",
                "Complete 60 second serves"
            ],
            metrics: ["In %", "Bounce height", "Kick effectiveness"],
            tips: [
                "Toss behind head for kick",
                "Brush up back of ball",
                "Accept less power for consistency"
            ],
            sport: .tennis
        ),
        
        // Return
        TrainingDrill(
            name: "Return of Serve Positioning",
            description: "Learn optimal return positioning",
            category: .returnOfServe,
            difficulty: .beginner,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Partner serving"],
            instructions: [
                "Practice returning from different positions",
                "Adjust position based on serve speed",
                "Focus on getting racket on every serve",
                "Track return success rate",
                "Complete 50 return attempts"
            ],
            metrics: ["Returns in play", "Return winners"],
            tips: [
                "Split step as server hits",
                "Shorten backswing on fast serves",
                "Move forward on weak serves"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Aggressive Returns",
            description: "Practice attacking second serves",
            category: .returnOfServe,
            difficulty: .advanced,
            duration: 25,
            equipment: ["Tennis balls", "Racket", "Partner", "Court"],
            instructions: [
                "Step in on second serves",
                "Take ball early and on the rise",
                "Aim for depth or angles",
                "Practice return winners",
                "Complete 40 aggressive returns"
            ],
            metrics: ["Return winners", "Depth", "Attack success"],
            tips: [
                "Read the toss early",
                "Move forward into the court",
                "Be aggressive but controlled"
            ],
            sport: .tennis
        ),
        
        // Footwork
        TrainingDrill(
            name: "Split Step Timing",
            description: "Master the most important footwork in tennis",
            category: .tennisFootwork,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Tennis balls", "Racket", "Partner"],
            instructions: [
                "Split step as partner makes contact",
                "React and move to the ball",
                "Return to ready position",
                "Repeat for 10 minutes",
                "Focus on timing, not height"
            ],
            metrics: ["Timing accuracy", "First step quickness"],
            tips: [
                "Land as opponent hits ball",
                "Stay on balls of feet",
                "Push off explosively"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Side-to-Side Movement",
            description: "Build lateral court coverage",
            category: .tennisFootwork,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Partner or ball machine"],
            instructions: [
                "Partner feeds alternating wide shots",
                "Recover to center after each shot",
                "Focus on efficient movement patterns",
                "Complete 50 wide ball retrievals",
                "Track recovery time"
            ],
            metrics: ["Recovery time", "Balls reached"],
            tips: [
                "Use crossover steps for distance",
                "Small adjustment steps near ball",
                "Push off outside foot to recover"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Approach and Transition",
            description: "Move from baseline to net smoothly",
            category: .tennisFootwork,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Partner", "Court"],
            instructions: [
                "Hit approach shot and move forward",
                "Split step before partner's shot",
                "Close to net for volley",
                "Practice on both wings",
                "Complete 30 transitions"
            ],
            metrics: ["Successful approaches", "Net position quality"],
            tips: [
                "Move forward immediately after hitting",
                "Split step inside service line",
                "Be ready to volley or cover lob"
            ],
            sport: .tennis
        ),
        
        // Volley
        TrainingDrill(
            name: "Volley Wall Practice",
            description: "Build volley touch and reflexes",
            category: .volley,
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
            name: "Net Positioning and Volleys",
            description: "Master net play and finishing",
            category: .volley,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Partner", "Court"],
            instructions: [
                "Start at service line, move to net",
                "Partner feeds volleys to both sides",
                "Practice punch volleys for depth",
                "Practice drop volleys for touch",
                "Complete 50 volleys"
            ],
            metrics: ["Volley winners", "Errors", "Placement"],
            tips: [
                "Move forward to ball",
                "Firm wrist on contact",
                "Aim crosscourt for safety"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Overhead Smash",
            description: "Develop powerful and accurate overheads",
            category: .volley,
            difficulty: .intermediate,
            duration: 15,
            equipment: ["Tennis balls", "Racket", "Partner", "Court"],
            instructions: [
                "Partner lobs over your head",
                "Position under the ball",
                "Execute overhead smash",
                "Aim for open court",
                "Complete 30 overheads"
            ],
            metrics: ["Winners", "Errors", "Footwork quality"],
            tips: [
                "Point at ball with non-racket hand",
                "Use serve motion",
                "Hit through the ball"
            ],
            sport: .tennis
        ),
        
        // Consistency
        TrainingDrill(
            name: "Baseline Rally Consistency",
            description: "Build ability to sustain long rallies",
            category: .consistency,
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
            name: "Crosscourt Rally Drill",
            description: "Master high-percentage crosscourt shots",
            category: .consistency,
            difficulty: .beginner,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Partner", "Court"],
            instructions: [
                "Rally only crosscourt with partner",
                "Keep ball deep and safe",
                "Try for 30+ shot rallies",
                "Track longest rally",
                "Complete 15 minutes"
            ],
            metrics: ["Longest rally", "Unforced errors"],
            tips: [
                "Use net clearance (3-4 feet)",
                "Crosscourt is safest shot",
                "Stay patient and consistent"
            ],
            sport: .tennis
        ),
        
        // Movement
        TrainingDrill(
            name: "Court Coverage Drill",
            description: "Improve speed and agility around the court",
            category: .movement,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Partner or ball machine"],
            instructions: [
                "Partner feeds to all four corners",
                "Retrieve every ball and return to center",
                "Track balls successfully returned",
                "Complete 60 balls",
                "Rest 2 minutes between sets"
            ],
            metrics: ["Balls reached", "Quality returns"],
            tips: [
                "Anticipate from opponent's position",
                "Use efficient movement patterns",
                "Recover quickly to center"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Reaction Ball Drill",
            description: "Build quick first-step explosiveness",
            category: .movement,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Tennis balls", "Racket", "Partner"],
            instructions: [
                "Start at center baseline",
                "Partner feeds unpredictable balls",
                "React and get to every ball",
                "Focus on first three steps",
                "Complete 40 reaction movements"
            ],
            metrics: ["Balls reached", "First step time"],
            tips: [
                "Stay in ready position",
                "Read opponent's racket",
                "Explode to the ball"
            ],
            sport: .tennis
        ),
        
        // Conditioning
        TrainingDrill(
            name: "Tennis-Specific Intervals",
            description: "Build match endurance",
            category: .tennisConditioning,
            difficulty: .intermediate,
            duration: 25,
            equipment: ["Court", "Timer"],
            instructions: [
                "Sprint baseline to net and back: 30 seconds",
                "Rest 30 seconds",
                "Side shuffle line to line: 30 seconds",
                "Rest 30 seconds",
                "Complete 10 rounds"
            ],
            metrics: ["Reps completed", "Times"],
            tips: [
                "Maintain intensity throughout",
                "Use proper movement patterns",
                "This mimics match demands"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Point Play Conditioning",
            description: "Build endurance through competitive points",
            category: .tennisConditioning,
            difficulty: .advanced,
            duration: 30,
            equipment: ["Tennis balls", "Racket", "Partner", "Court"],
            instructions: [
                "Play out full points",
                "First to 11 points wins set",
                "Play 3-5 sets",
                "No rest between points",
                "Track performance over time"
            ],
            metrics: ["Points won", "Endurance level"],
            tips: [
                "Stay focused when tired",
                "Use this to build mental toughness",
                "Simulate match conditions"
            ],
            sport: .tennis
        ),
        
        // Match Preparation
        TrainingDrill(
            name: "Practice Match Scenarios",
            description: "Simulate pressure situations",
            category: .matchPrep,
            difficulty: .advanced,
            duration: 30,
            equipment: ["Tennis balls", "Racket", "Partner", "Court"],
            instructions: [
                "Play points from specific scenarios",
                "Practice serving at 30-40",
                "Practice returning at break point",
                "Practice tiebreak situations",
                "Complete 20 pressure points"
            ],
            metrics: ["Conversion rate", "Mental toughness"],
            tips: [
                "Embrace the pressure",
                "Stick to your patterns",
                "Practice winning ugly"
            ],
            sport: .tennis
        ),
        TrainingDrill(
            name: "Strategic Point Play",
            description: "Develop tactical awareness and patterns",
            category: .matchPrep,
            difficulty: .advanced,
            duration: 25,
            equipment: ["Tennis balls", "Racket", "Partner", "Court"],
            instructions: [
                "Play points with specific patterns",
                "Serve and volley points",
                "Baseline grinder points",
                "Aggressive baseline points",
                "Track what works for you"
            ],
            metrics: ["Pattern success rate", "Point wins"],
            tips: [
                "Know your strengths",
                "Have a plan for each point",
                "Adapt based on opponent"
            ],
            sport: .tennis
        ),
        
        // Accuracy
        TrainingDrill(
            name: "Target Practice",
            description: "Improve shot placement and control",
            category: .accuracy,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Tennis balls", "Racket", "Court", "Target cones or markers"],
            instructions: [
                "Place targets in all four corners",
                "Hit 10 shots to each target",
                "Practice from various court positions",
                "Track accuracy percentage",
                "Increase difficulty with movement"
            ],
            metrics: ["Target hits", "Accuracy %", "Depth control"],
            tips: [
                "Aim small, miss small",
                "Visualize the target before hitting",
                "Follow through toward target"
            ],
            sport: .tennis
        )
    ]
    
    // MARK: - Football Drills
    
    static let footballDrills: [TrainingDrill] = [
        // QB Drills
        TrainingDrill(
            name: "QB Throwing Mechanics",
            description: "Perfect your throwing motion and accuracy",
            category: .qbDrills,
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
            name: "Pocket Movement",
            description: "Learn to feel pressure and move in the pocket",
            category: .qbDrills,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Football", "Cones", "Partner rusher"],
            instructions: [
                "Set up pocket with cones",
                "Partner applies pressure from edges",
                "Step up and slide within pocket",
                "Keep eyes downfield",
                "Complete 15 reps"
            ],
            metrics: ["Clean pockets", "Completions under pressure"],
            tips: [
                "Feel the rush, don't watch it",
                "Climb the pocket when edge collapses",
                "Keep throwing base under you"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Three-Step Drop",
            description: "Master quick game footwork and timing",
            category: .qbDrills,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Football", "Cones for landmarks"],
            instructions: [
                "Practice 3-step drop footwork",
                "Plant and throw on rhythm",
                "Hit quick slants and hitches",
                "Focus on timing with receiver",
                "Complete 20 throws"
            ],
            metrics: ["Timing", "Accuracy", "Footwork score"],
            tips: [
                "Short, choppy steps",
                "Ball comes out on time",
                "Eyes to target immediately"
            ],
            sport: .football
        ),
        
        // WR Drills
        TrainingDrill(
            name: "Route Tree Mastery",
            description: "Perfect execution of all route combinations",
            category: .wrDrills,
            difficulty: .intermediate,
            duration: 25,
            equipment: ["Football", "Cones", "Partner QB"],
            instructions: [
                "Practice full route tree: slant, out, curl, post, corner, go",
                "Focus on sharp cuts at break points",
                "Track ball with eyes before catch",
                "Run each route 5 times",
                "Full speed every rep"
            ],
            metrics: ["Catches", "Drop rate", "Separation"],
            tips: [
                "Sell the route with eyes and body",
                "Plant and drive out of breaks",
                "Secure the catch first"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Release Package",
            description: "Beat press coverage off the line",
            category: .wrDrills,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Cones or partner DB"],
            instructions: [
                "Practice inside release",
                "Practice outside release",
                "Use swim move technique",
                "Use rip technique",
                "Complete 15 reps each technique"
            ],
            metrics: ["Clean releases", "Time to separation"],
            tips: [
                "Attack the defender's leverage",
                "Get hands on them first",
                "Explode after the release"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Ball Tracking",
            description: "Improve over-the-shoulder catches",
            category: .wrDrills,
            difficulty: .intermediate,
            duration: 15,
            equipment: ["Football", "Partner QB"],
            instructions: [
                "Run streaks and deep posts",
                "Track ball over shoulder",
                "Adjust speed to ball flight",
                "Catch at highest point",
                "Complete 20 deep balls"
            ],
            metrics: ["Catches", "Adjustments made"],
            tips: [
                "Find the ball early",
                "Match QB's trajectory",
                "Catch with hands, not body"
            ],
            sport: .football
        ),
        
        // Route Running
        TrainingDrill(
            name: "Stem and Break",
            description: "Create separation with route technique",
            category: .routeRunning,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Cones", "Football"],
            instructions: [
                "Push vertical at DB for 5-7 yards",
                "Set up break with head/shoulder fake",
                "Plant outside foot and explode",
                "Create 2-3 yards separation",
                "Practice curls, outs, comebacks"
            ],
            metrics: ["Separation distance", "Break timing"],
            tips: [
                "Threaten vertical first",
                "Plant foot closest to sideline",
                "Accelerate out of the break"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Double Moves",
            description: "Master advanced route combinations",
            category: .routeRunning,
            difficulty: .advanced,
            duration: 25,
            equipment: ["Cones", "Football", "Partner"],
            instructions: [
                "Practice hitch-and-go",
                "Practice comeback-and-go",
                "Practice slant-and-go",
                "Sell first move completely",
                "Complete 10 reps per route"
            ],
            metrics: ["Successful fakes", "Big plays created"],
            tips: [
                "Make defender bite on first move",
                "Explode on second move",
                "Eyes to QB on both breaks"
            ],
            sport: .football
        ),
        
        // Catching
        TrainingDrill(
            name: "Hands Catching",
            description: "Build strong, reliable hands",
            category: .footballCatching,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Football", "Partner"],
            instructions: [
                "Catch with hands only, no body",
                "Partner throws from 5 yards",
                "High, low, left, right targets",
                "Focus on hand position",
                "Complete 50 catches"
            ],
            metrics: ["Catches", "Drops", "Hand catches %"],
            tips: [
                "Thumbs together for high balls",
                "Pinkies together for low balls",
                "Watch ball into your hands"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Concentration Catches",
            description: "Maintain focus through contact",
            category: .footballCatching,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Football", "2 partners"],
            instructions: [
                "Partner throws, other provides contact",
                "Catch through the distraction",
                "Tuck ball immediately after catch",
                "Turn upfield",
                "Complete 25 contested catches"
            ],
            metrics: ["Catches under contact", "Fumbles"],
            tips: [
                "Eyes on ball through contact",
                "Secure before turning",
                "Expect to be hit"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "One-Handed Catches",
            description: "Extend catching radius and body control",
            category: .footballCatching,
            difficulty: .advanced,
            duration: 15,
            equipment: ["Football", "Partner"],
            instructions: [
                "Practice right hand only catches",
                "Practice left hand only catches",
                "Work on sideline toe-tap catches",
                "Complete 20 per hand"
            ],
            metrics: ["One-hand catches", "Success rate"],
            tips: [
                "Extend fully to the ball",
                "Palm the ball, fingers spread",
                "Bring it in quickly"
            ],
            sport: .football
        ),
        
        // RB Drills
        TrainingDrill(
            name: "Ball Security & Carrying",
            description: "Master ball protection techniques",
            category: .rbDrills,
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
                "Five points of pressure on ball",
                "Cover ball in traffic",
                "Switch arms away from defenders"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Vision and Cuts",
            description: "Read blocks and make decisive cuts",
            category: .rbDrills,
            difficulty: .intermediate,
            duration: 25,
            equipment: ["Football", "Cones or bags", "Blockers"],
            instructions: [
                "Set up blockers as offensive line",
                "Read blocking schemes",
                "Press hole and cut upfield",
                "One cut and go mentality",
                "Complete 20 reps"
            ],
            metrics: ["Yards after decision", "Hesitations"],
            tips: [
                "Press the line of scrimmage",
                "Cut off lead blocker's hip",
                "Accelerate through the cut"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Pass Protection",
            description: "Learn to pick up blitzers and protect QB",
            category: .rbDrills,
            difficulty: .advanced,
            duration: 20,
            equipment: ["Partner rusher"],
            instructions: [
                "Identify blitzer pre-snap",
                "Engage with proper technique",
                "Keep inside leverage",
                "Punch and reset",
                "Complete 15 reps"
            ],
            metrics: ["Successful blocks", "QB hits allowed"],
            tips: [
                "See the blitzer, set your feet",
                "Low pad level wins",
                "Keep QB protected at all costs"
            ],
            sport: .football
        ),
        
        // DB Drills
        TrainingDrill(
            name: "Backpedal and Break",
            description: "Master defensive back footwork fundamentals",
            category: .dbDrills,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Cones"],
            instructions: [
                "Backpedal for 10 yards",
                "Break at 45-degree angle on command",
                "Plant and drive to the ball",
                "Practice both directions",
                "Complete 15 reps each way"
            ],
            metrics: ["Break time", "Clean plants"],
            tips: [
                "Stay low in backpedal",
                "Plant outside foot to break",
                "Drive hard out of the break"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Press Coverage",
            description: "Learn to jam receivers at the line",
            category: .dbDrills,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Partner WR"],
            instructions: [
                "Line up in press position",
                "Jam receiver at line of scrimmage",
                "Maintain outside leverage",
                "Mirror receiver's movements",
                "Complete 20 reps"
            ],
            metrics: ["Successful jams", "Releases allowed"],
            tips: [
                "Hands inside receiver's frame",
                "Keep feet moving",
                "Force receiver to your help"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Ball Skills",
            description: "Practice high-pointing and intercepting passes",
            category: .dbDrills,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Football", "Partner QB"],
            instructions: [
                "Practice tracking and catching thrown balls",
                "High-point the ball at its peak",
                "Work on one-handed grabs",
                "Practice rip-through on contested balls",
                "Complete 25 reps"
            ],
            metrics: ["Interceptions", "Pass breakups"],
            tips: [
                "Play the ball, not the receiver",
                "Attack the ball at highest point",
                "Secure and tuck immediately"
            ],
            sport: .football
        ),
        
        // Footwork
        TrainingDrill(
            name: "Ladder Footwork",
            description: "Build foot speed and coordination",
            category: .footballFootwork,
            difficulty: .beginner,
            duration: 15,
            equipment: ["Agility ladder"],
            instructions: [
                "High knees through ladder",
                "Lateral shuffle through ladder",
                "Icky shuffle pattern",
                "In-in-out-out pattern",
                "Complete 5 rounds"
            ],
            metrics: ["Clean runs", "Time"],
            tips: [
                "Stay on balls of feet",
                "Quick, choppy steps",
                "Maintain proper posture"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "5-Cone Drill (Pro Agility)",
            description: "Improve change of direction at game speed",
            category: .footballFootwork,
            difficulty: .intermediate,
            duration: 15,
            equipment: ["5 Cones"],
            instructions: [
                "Set up 5-cone pattern",
                "Run L-drill portion",
                "Run full pattern timed",
                "Focus on sharp cuts",
                "Complete 10 reps"
            ],
            metrics: ["Time", "Best time"],
            tips: [
                "Stay low through cuts",
                "Plant and push explosively",
                "Keep shoulders square to target"
            ],
            sport: .football
        ),
        
        // Speed & Agility
        TrainingDrill(
            name: "40-Yard Dash Technique",
            description: "Perfect your start and acceleration",
            category: .speedAgility,
            difficulty: .beginner,
            duration: 20,
            equipment: ["40-yard marked course", "Timer"],
            instructions: [
                "Practice 3-point stance start",
                "Focus on first 3 explosive steps",
                "Transition to upright running",
                "Complete 8 full runs",
                "Rest 2-3 minutes between"
            ],
            metrics: ["40-time", "10-yard split", "Best time"],
            tips: [
                "Explode on first step",
                "Drive knees and pump arms",
                "Don't stand up too early"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Shuttle Runs",
            description: "Build conditioning and change of direction",
            category: .speedAgility,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Cones or lines"],
            instructions: [
                "5-10-5 shuttle: touch lines at 5 and 10 yards",
                "Complete in under 4.5 seconds",
                "Rest until minute mark",
                "Complete 10 shuttles",
                "Track all times"
            ],
            metrics: ["Times", "Average", "Best"],
            tips: [
                "Touch line with hand",
                "Plant and explode",
                "Stay low on turns"
            ],
            sport: .football
        ),
        
        // Conditioning
        TrainingDrill(
            name: "Gassers",
            description: "Build football-specific endurance",
            category: .footballConditioning,
            difficulty: .advanced,
            duration: 25,
            equipment: ["Football field"],
            instructions: [
                "Sprint sideline to sideline and back (4 total)",
                "Complete in under 60 seconds",
                "Rest 2 minutes between",
                "Complete 6-8 total gassers",
                "Must finish all under time"
            ],
            metrics: ["Times", "Completion rate"],
            tips: [
                "Pace first two runs",
                "Mental toughness is key",
                "Touch each sideline"
            ],
            sport: .football
        ),
        TrainingDrill(
            name: "Position-Specific Conditioning",
            description: "Simulate game-like conditioning demands",
            category: .footballConditioning,
            difficulty: .intermediate,
            duration: 20,
            equipment: ["Field", "Football"],
            instructions: [
                "Simulate your position for 10 plays",
                "Full effort on each rep",
                "Rest 30 seconds between plays",
                "Complete 3 sets of 10",
                "Track effort and recovery"
            ],
            metrics: ["Reps completed", "Effort level"],
            tips: [
                "Go game speed",
                "Stay focused when tired",
                "This builds mental toughness"
            ],
            sport: .football
        )
    ]
    
    // Volleyball and Baseball drills removed - sports not currently supported
}

#Preview {
    DrillLibraryView(sport: .basketball)
}
