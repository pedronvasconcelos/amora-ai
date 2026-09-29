import SwiftUI

/// Who a desktop pet follows. `everyone` reacts to Cursor, Codex, and Claude Code together.
enum PetScope: String, Codable, CaseIterable, Identifiable, Equatable {
    case everyone
    case cursor
    case codex
    case claude

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyone: "All agents"
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }

    var source: ActivityEvent.Source? {
        switch self {
        case .everyone: nil
        case .cursor: .cursor
        case .codex: .codex
        case .claude: .claude
        }
    }
}

enum PetCoat: Equatable {
    case blueMerle
    case blackAndWhite
    case slateMerle
    case brownAndWhite
}

struct BuiltinPet: Equatable {
    var name: String
    var coat: PetCoat
}

func builtinPet(for scope: PetScope) -> BuiltinPet {
    switch scope {
    case .everyone: BuiltinPet(name: "Amora", coat: .blueMerle)
    case .cursor: BuiltinPet(name: "Luna", coat: .blackAndWhite)
    case .codex: BuiltinPet(name: "Storm", coat: .slateMerle)
    case .claude: BuiltinPet(name: "Duna", coat: .brownAndWhite)
    }
}

func petDisplayName(scope: PetScope, modelName: String?) -> String {
    modelName ?? builtinPet(for: scope).name
}

func agentsForPet(scope: PetScope, agents: [AgentActivity]) -> [AgentActivity] {
    guard let source = scope.source else { return agents }
    return agents.filter { $0.source == source }
}

/// What a pet mirrors. With a pet per session it takes the first open session it follows,
/// and its companions take the rest; with none open it shows what its agents last reported.
func agentsForPet(
    scope: PetScope,
    perSession: Bool,
    sessions: [AgentActivity],
    agents: [AgentActivity]
) -> [AgentActivity] {
    if perSession, let first = agentsForPet(scope: scope, agents: sessions).first {
        return [first]
    }
    return agentsForPet(scope: scope, agents: agents)
}

/// The sessions that get a companion beside a pet: every one it follows after its own, up to the limit.
func companionSessions(scope: PetScope, sessions: [AgentActivity]) -> [AgentActivity] {
    Array(agentsForPet(scope: scope, agents: sessions).dropFirst().prefix(PetMetrics.maximumCompanions))
}

struct PetRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }
}

struct PetCoatPatch: Equatable {
    var centerX: Double
    var centerY: Double
    var width: Double
    var height: Double
    var angle: Double
    var dark: Bool
}

struct PetCoatDefinition: Equatable {
    var base: PetRGB
    var dark: PetRGB
    var light: PetRGB
    var white: PetRGB
    var innerEar: PetRGB
    var leftEye: PetRGB
    var rightEye: PetRGB
    var showPoints: Bool
    var leftEarFolded: Bool
    var rightEarFolded: Bool
    var blazeOffset: Double
    var blazeScale: Double
    var patches: [PetCoatPatch]
}

func coatDefinition(_ coat: PetCoat) -> PetCoatDefinition {
    switch coat {
    case .blueMerle:
        PetCoatDefinition(
            base: PetRGB(red: 0.60, green: 0.65, blue: 0.72),
            dark: PetRGB(red: 0.21, green: 0.24, blue: 0.29),
            light: PetRGB(red: 0.78, green: 0.82, blue: 0.87),
            white: PetRGB(red: 0.97, green: 0.96, blue: 0.94),
            innerEar: PetRGB(red: 0.83, green: 0.66, blue: 0.67),
            leftEye: PetRGB(red: 0.42, green: 0.26, blue: 0.16),
            rightEye: PetRGB(red: 0.42, green: 0.72, blue: 0.92),
            showPoints: true,
            leftEarFolded: false,
            rightEarFolded: true,
            blazeOffset: 1.5,
            blazeScale: 1,
            patches: [
                PetCoatPatch(centerX: -20, centerY: -20, width: 30, height: 22, angle: -20, dark: true),
                PetCoatPatch(centerX: 22, centerY: -8, width: 24, height: 32, angle: 15, dark: true),
                PetCoatPatch(centerX: -28, centerY: 8, width: 14, height: 18, angle: 0, dark: true),
                PetCoatPatch(centerX: 10, centerY: -28, width: 10, height: 7, angle: 30, dark: true),
                PetCoatPatch(centerX: 26, centerY: 16, width: 9, height: 7, angle: 0, dark: true),
                PetCoatPatch(centerX: -12, centerY: -28, width: 12, height: 8, angle: 10, dark: false),
                PetCoatPatch(centerX: 18, centerY: -20, width: 8, height: 6, angle: -25, dark: false),
                PetCoatPatch(centerX: -22, centerY: -4, width: 7, height: 9, angle: 0, dark: false),
                PetCoatPatch(centerX: 28, centerY: 2, width: 6, height: 8, angle: 0, dark: false),
            ]
        )
    case .blackAndWhite:
        PetCoatDefinition(
            base: PetRGB(red: 0.10, green: 0.10, blue: 0.11),
            dark: PetRGB(red: 0.05, green: 0.05, blue: 0.06),
            light: PetRGB(red: 0.22, green: 0.22, blue: 0.24),
            white: PetRGB(red: 0.97, green: 0.96, blue: 0.94),
            innerEar: PetRGB(red: 0.72, green: 0.56, blue: 0.58),
            leftEye: PetRGB(red: 0.33, green: 0.20, blue: 0.12),
            rightEye: PetRGB(red: 0.33, green: 0.20, blue: 0.12),
            showPoints: false,
            leftEarFolded: false,
            rightEarFolded: false,
            blazeOffset: 0,
            blazeScale: 1.45,
            patches: []
        )
    case .slateMerle:
        // Neutral silver-charcoal merle. Amora's blue merle stays blue-tinted, tan-pointed, and odd-eyed.
        PetCoatDefinition(
            base: PetRGB(red: 0.55, green: 0.56, blue: 0.58),
            dark: PetRGB(red: 0.18, green: 0.19, blue: 0.20),
            light: PetRGB(red: 0.74, green: 0.75, blue: 0.76),
            white: PetRGB(red: 0.96, green: 0.96, blue: 0.95),
            innerEar: PetRGB(red: 0.75, green: 0.68, blue: 0.70),
            leftEye: PetRGB(red: 0.62, green: 0.70, blue: 0.74),
            rightEye: PetRGB(red: 0.62, green: 0.70, blue: 0.74),
            showPoints: false,
            leftEarFolded: true,
            rightEarFolded: false,
            blazeOffset: -4,
            blazeScale: 0.8,
            patches: [
                PetCoatPatch(centerX: 18, centerY: -22, width: 22, height: 16, angle: 25, dark: true),
                PetCoatPatch(centerX: -16, centerY: -4, width: 18, height: 28, angle: -12, dark: true),
                PetCoatPatch(centerX: 26, centerY: 12, width: 16, height: 12, angle: 8, dark: true),
                PetCoatPatch(centerX: -6, centerY: -26, width: 14, height: 10, angle: -18, dark: true),
                PetCoatPatch(centerX: -26, centerY: 16, width: 12, height: 14, angle: 4, dark: true),
                PetCoatPatch(centerX: 6, centerY: -14, width: 11, height: 8, angle: 12, dark: false),
                PetCoatPatch(centerX: -14, centerY: -18, width: 8, height: 6, angle: 20, dark: false),
                PetCoatPatch(centerX: 22, centerY: -2, width: 7, height: 11, angle: -8, dark: false),
                PetCoatPatch(centerX: 0, centerY: 8, width: 10, height: 7, angle: 0, dark: false),
                PetCoatPatch(centerX: -30, centerY: -10, width: 8, height: 8, angle: 0, dark: true),
            ]
        )
    case .brownAndWhite:
        PetCoatDefinition(
            base: PetRGB(red: 0.48, green: 0.30, blue: 0.18),
            dark: PetRGB(red: 0.32, green: 0.18, blue: 0.10),
            light: PetRGB(red: 0.62, green: 0.42, blue: 0.28),
            white: PetRGB(red: 0.97, green: 0.96, blue: 0.94),
            innerEar: PetRGB(red: 0.86, green: 0.62, blue: 0.55),
            leftEye: PetRGB(red: 0.78, green: 0.52, blue: 0.22),
            rightEye: PetRGB(red: 0.78, green: 0.52, blue: 0.22),
            showPoints: false,
            leftEarFolded: true,
            rightEarFolded: true,
            blazeOffset: 2.5,
            blazeScale: 1.2,
            patches: []
        )
    }
}
