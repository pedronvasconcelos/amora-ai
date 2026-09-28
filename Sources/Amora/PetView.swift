import SwiftUI

enum PetPose: Equatable {
    case resting
    case thinking
    case working
    case waiting
    case finished
}

func petPose(for activity: ActivityEvent.Activity?) -> PetPose {
    switch activity {
    case nil: .resting
    case .thinking: .thinking
    case .working: .working
    case .waiting: .waiting
    case .finished: .finished
    }
}

func petAccessibilityLabel(for agents: [AgentActivity], isActive: Bool = false, name: String = "Amora") -> String {
    let base: String
    if agents.isEmpty {
        base = "\(name), resting"
    } else {
        base = agents.map { agent in
            if let project = agent.project {
                return "\(agent.source.displayName), \(agent.activity.rawValue), \(project)"
            }
            return "\(agent.source.displayName), \(agent.activity.rawValue)"
        }.joined(separator: "; ")
    }
    return isActive ? "\(base), active" : base
}

struct PetView: View {
    @ObservedObject var state: ActivityState
    @ObservedObject var preferences: PetPreferences
    @ObservedObject var library: PetModelLibrary
    let petID: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool { preferences.activePetID == petID }
    private var model: PetModel? { library.model(id: preferences.pet(petID)?.modelID) }

    var body: some View {
        let agents = state.agents
        let pose = petPose(for: leadingActivity(agents)?.activity)
        Group {
            if let model {
                PetSpriteFigure(sprite: model.sprite, animation: petAnimation(for: pose), reduceMotion: reduceMotion)
                    .padding(10)
            } else {
                PetFigure(pose: pose, reduceMotion: reduceMotion)
            }
        }
        .frame(width: PetMetrics.size.width, height: PetMetrics.size.height)
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(PetPalette.ink.opacity(0.35), lineWidth: 1.5)
                    .padding(8)
            }
        }
        .overlay(alignment: .bottom) {
            if !agents.isEmpty {
                HStack(spacing: 3) {
                    ForEach(agents) { AgentActivityBadge(agent: $0) }
                }
                .padding(.bottom, 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(petAccessibilityLabel(
            for: agents,
            isActive: isActive,
            name: model?.manifest.displayName ?? "Amora"
        ))
    }
}

private struct AgentActivityBadge: View {
    let agent: AgentActivity

    var body: some View {
        HStack(spacing: 2) {
            Text(agent.source.monogram)
            Image(systemName: agent.activity.symbolName)
        }
        .font(.system(size: 8, weight: .bold, design: .rounded))
        .foregroundStyle(agent.activity == .waiting ? Color.white : PetPalette.ink)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(agent.activity == .waiting ? PetPalette.innerEar : PetPalette.belly)
        )
    }
}

struct PetSpriteFigure: View {
    static let frameDuration: TimeInterval = 0.12

    let sprite: PetSprite
    let animation: PetAnimation
    var reduceMotion: Bool
    @State private var started = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameDuration, paused: reduceMotion)) { timeline in
            let frames = sprite.frames(for: animation)
            let index = reduceMotion ? 0 : spriteFrameIndex(
                elapsed: timeline.date.timeIntervalSince(started),
                frameDuration: Self.frameDuration,
                frameCount: frames.count
            )
            if frames.indices.contains(index) {
                Image(decorative: frames[index], scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .onChange(of: animation) { _, _ in
            started = Date()
        }
    }
}

struct PetModelThumbnail: View {
    let model: PetModel?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let image = model?.sprite.thumbnail {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(PetPalette.body)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct PetFigure: View {
    let pose: PetPose
    var reduceMotion: Bool
    @State private var poseStarted = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let clock = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let elapsed = timeline.date.timeIntervalSince(poseStarted)
            figure(clock: clock, elapsed: elapsed)
        }
        .onChange(of: pose) { _, _ in
            poseStarted = Date()
        }
    }

    private func figure(clock: TimeInterval, elapsed: TimeInterval) -> some View {
        let hop = hopOffset(elapsed: elapsed)
        let bob = bodyOffset(clock: clock)
        return ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.16))
                .frame(width: hop < -2 ? 28 : 40, height: 10)
                .offset(y: 46)
            VStack(spacing: -18) {
                ears
                torso(clock: clock)
            }
            .offset(y: bob + hop)
            .scaleEffect(pose == .resting && !reduceMotion ? 1 + sin(clock * 1.2) * 0.018 : 1, anchor: .bottom)
        }
    }

    private var ears: some View {
        HStack(spacing: 22) {
            ear(tilt: pose == .thinking ? -14 : 0)
            ear(tilt: pose == .thinking ? 14 : 0)
        }
        .offset(y: 8)
    }

    private func ear(tilt: Double) -> some View {
        ZStack {
            EarShape()
                .fill(PetPalette.body)
                .frame(width: 22, height: 26)
            EarShape()
                .fill(PetPalette.innerEar)
                .frame(width: 11, height: 14)
                .offset(y: 4)
        }
        .rotationEffect(.degrees(tilt))
    }

    private func torso(clock: TimeInterval) -> some View {
        ZStack {
            Circle()
                .fill(PetPalette.body)
                .frame(width: 72, height: 72)
            Circle()
                .fill(PetPalette.belly)
                .frame(width: 36, height: 30)
                .offset(y: 14)
            face(clock: clock)
            if pose == .waiting {
                Circle()
                    .fill(PetPalette.body)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().fill(PetPalette.belly).frame(width: 8, height: 8))
                    .offset(x: 28, y: -8)
            }
            if pose == .working {
                HStack(spacing: 22) {
                    Circle().fill(PetPalette.body).frame(width: 12, height: 12)
                    Circle().fill(PetPalette.body).frame(width: 12, height: 12)
                }
                .offset(y: 28)
            }
        }
    }

    private func face(clock: TimeInterval) -> some View {
        VStack(spacing: 6) {
            eyes(clock: clock)
            mouth
        }
        .offset(y: -2)
    }

    private func eyes(clock: TimeInterval) -> some View {
        let look: CGFloat = {
            guard pose == .thinking else { return 0 }
            return reduceMotion ? 3 : sin(clock * 1.2) * 3
        }()
        return HStack(spacing: 14) {
            eye
            eye
        }
        .offset(x: look)
    }

    private var eye: some View {
        Group {
            switch pose {
            case .resting:
                Capsule()
                    .fill(PetPalette.ink)
                    .frame(width: 10, height: 3)
            case .finished:
                Capsule()
                    .fill(PetPalette.ink)
                    .frame(width: 10, height: 5)
                    .offset(y: 2)
            case .waiting:
                Circle()
                    .fill(PetPalette.ink)
                    .frame(width: 8, height: 8)
            case .thinking, .working:
                Circle()
                    .fill(PetPalette.ink)
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var mouth: some View {
        Group {
            switch pose {
            case .finished:
                ArcMouth()
                    .stroke(PetPalette.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 12, height: 6)
            case .waiting:
                Capsule()
                    .fill(PetPalette.ink)
                    .frame(width: 4, height: 4)
            default:
                Capsule()
                    .fill(PetPalette.ink.opacity(0.7))
                    .frame(width: 8, height: 2)
            }
        }
    }

    private func bodyOffset(clock: TimeInterval) -> CGFloat {
        if reduceMotion { return 0 }
        switch pose {
        case .resting:
            return 0
        case .thinking:
            return sin(clock * 1.6) * 3
        case .working:
            return sin(clock * 9) * 5
        case .waiting:
            return sin(clock * 2.2) * 1.5
        case .finished:
            return 0
        }
    }

    private func hopOffset(elapsed: TimeInterval) -> CGFloat {
        guard pose == .finished, !reduceMotion else { return 0 }
        let duration = 0.55
        guard elapsed >= 0, elapsed < duration else { return 0 }
        return -sin(elapsed / duration * .pi) * 18
    }
}

private enum PetPalette {
    static let body = Color(red: 0.93, green: 0.47, blue: 0.33)
    static let belly = Color(red: 0.99, green: 0.86, blue: 0.74)
    static let innerEar = Color(red: 0.84, green: 0.36, blue: 0.34)
    static let ink = Color(red: 0.24, green: 0.16, blue: 0.14)
}

private struct EarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.minY + 4))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.maxY + 6))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY + 4))
        return path
    }
}

private struct ArcMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
