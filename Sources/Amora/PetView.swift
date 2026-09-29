import SwiftUI

enum PetPose: Equatable {
    case resting
    case thinking
    case working
    case waiting
    case finished
    case reminding
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

/// An agent waiting on the user still wins; otherwise an imminent calendar event takes over the pose.
func petPose(for activity: ActivityEvent.Activity?, hasImminentEvent: Bool) -> PetPose {
    guard hasImminentEvent, activity != .waiting else { return petPose(for: activity) }
    return .reminding
}

func petContentScale(in size: CGSize, fallback: CGFloat) -> CGFloat {
    guard size.width > 1, size.height > 1 else { return fallback }
    return min(size.width / PetMetrics.size.width, size.height / PetMetrics.size.height)
}

func petAccessibilityLabel(
    for agents: [AgentActivity],
    isActive: Bool = false,
    name: String = "Amora",
    reminder: String? = nil
) -> String {
    var base: String
    if agents.isEmpty {
        base = reminder == nil ? "\(name), resting" : name
    } else {
        base = agents.map { agent in
            var parts = [agent.source.displayName]
            if agent.isSubagent {
                parts.append(agent.subagentType.map { "\($0) subagent" } ?? "subagent")
            }
            parts.append(agent.activity.rawValue)
            if let project = agent.project {
                parts.append(project)
            }
            return parts.joined(separator: ", ")
        }.joined(separator: "; ")
    }
    if let reminder {
        base += "; \(reminder)"
    }
    return isActive ? "\(base), active" : base
}

struct PetView: View {
    @ObservedObject var state: ActivityState
    @ObservedObject var preferences: PetPreferences
    @ObservedObject var library: PetModelLibrary
    @ObservedObject var agenda: CalendarAgenda
    let petID: UUID
    /// Set on a session companion: the session or subagent it mirrors. It keeps its pet's look.
    var session: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool { session == nil && preferences.activePetID == petID }
    private var scope: PetScope { preferences.pet(petID)?.scope ?? .everyone }
    private var model: PetModel? { library.model(id: preferences.pet(petID)?.modelID) }

    private var agents: [AgentActivity] {
        if let session {
            return state.sessions.filter { $0.id == session }
        }
        return agentsForPet(
            scope: scope,
            perSession: preferences.petPerSession,
            sessions: state.sessions,
            agents: state.agents
        )
    }

    var body: some View {
        let agents = self.agents
        let showsTag = (session != nil || preferences.petPerSession) && agents.count == 1
        // Only the pet itself reminds you of an event, so a pack of companions does not all wave at once.
        let imminent = session == nil ? agenda.imminent : nil
        let pose = petPose(for: leadingActivity(agents)?.activity, hasImminentEvent: imminent != nil)
        let coat = coatDefinition(builtinPet(for: scope).coat)
        GeometryReader { proxy in
            let scale = petContentScale(in: proxy.size, fallback: preferences.scale(for: petID))
            Group {
                if let model {
                    PetSpriteFigure(sprite: model.sprite, animation: petAnimation(for: pose), reduceMotion: reduceMotion)
                        .padding(10)
                } else {
                    PetFigure(pose: pose, coat: coat, reduceMotion: reduceMotion)
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
                        ForEach(agents) { AgentActivityBadge(agent: $0, showsTag: showsTag) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            }
            .overlay(alignment: .top) {
                if let imminent {
                    AgendaReminderBadge(countdown: agendaCountdown(imminent, now: agenda.now))
                        .padding(.top, 4)
                }
            }
            .scaleEffect(scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(petAccessibilityLabel(
            for: agents,
            isActive: isActive,
            name: petDisplayName(scope: scope, modelName: model?.manifest.displayName),
            reminder: imminent.map { agendaReminderDescription($0, now: agenda.now) }
        ))
    }
}

private struct AgendaReminderBadge: View {
    let countdown: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "calendar")
            Text(countdown)
        }
        .font(.system(size: 8, weight: .bold, design: .rounded))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Capsule().fill(PetPalette.copper))
    }
}

private struct AgentActivityBadge: View {
    let agent: AgentActivity
    var showsTag = false

    var body: some View {
        HStack(spacing: 2) {
            Text(agent.source.monogram)
            Image(systemName: agent.activity.symbolName)
            if showsTag, let tag = agent.tag {
                Text(tag)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: 8, weight: .bold, design: .rounded))
        .foregroundStyle(agent.activity == .waiting ? Color.white : PetPalette.ink)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(agent.activity == .waiting ? PetPalette.copper : PetPalette.coat)
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
    var coat: PetCoatDefinition = coatDefinition(.blueMerle)
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let image = model?.sprite.thumbnail {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                AmoraDrawing(coat: coat, pose: nil, clock: 0, reduceMotion: true)
                    .frame(width: AmoraDrawing.size.width, height: AmoraDrawing.size.height)
                    .scaleEffect(size / AmoraDrawing.size.height)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct PetFigure: View {
    let pose: PetPose
    let coat: PetCoatDefinition
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
                .frame(width: hop < -2 ? 26 : 36, height: 10)
                .offset(y: 46)
            AmoraDrawing(coat: coat, pose: pose, clock: clock, reduceMotion: reduceMotion)
                .offset(y: bob + hop)
                .scaleEffect(pose == .resting && !reduceMotion ? 1 + sin(clock * 1.2) * 0.018 : 1, anchor: .bottom)
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
        case .reminding:
            return sin(clock * 4) * 2
        }
    }

    private func hopOffset(elapsed: TimeInterval) -> CGFloat {
        guard pose == .finished, !reduceMotion else { return 0 }
        let duration = 0.55
        guard elapsed >= 0, elapsed < duration else { return 0 }
        return -sin(elapsed / duration * .pi) * 18
    }
}

/// A working-line border collie. The coat supplies color, markings, eyes, and ears.
/// A nil pose draws the neutral portrait used for thumbnails.
private struct AmoraDrawing: View {
    static let size = CGSize(width: 84, height: 88)

    let coat: PetCoatDefinition
    let pose: PetPose?
    let clock: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: -14) {
            ears
            torso(clock: clock)
        }
    }

    private var ears: some View {
        HStack(spacing: 18) {
            ear(tilt: pose == .thinking ? -22 : -12, folded: coat.leftEarFolded, spot: CGPoint(x: -3, y: 7))
            ear(tilt: pose == .thinking ? 2 : 14, folded: coat.rightEarFolded, spot: CGPoint(x: 3, y: 3))
        }
        .offset(y: 2)
    }

    private func ear(tilt: Double, folded: Bool, spot: CGPoint) -> some View {
        ZStack {
            EarShape()
                .fill(coat.base.color)
                .frame(width: 21, height: 30)
            Ellipse()
                .fill(coat.dark.color)
                .frame(width: 9, height: 9)
                .offset(x: spot.x, y: spot.y)
            EarShape()
                .fill(coat.innerEar.color)
                .frame(width: 9, height: 15)
                .offset(y: 6)
            if folded {
                // Semi-erect ear: the tip flops forward over the ear.
                EarShape()
                    .fill(coat.dark.color)
                    .frame(width: 12, height: 9)
                    .rotationEffect(.degrees(180))
                    .offset(y: -8)
            } else {
                EarShape()
                    .fill(coat.dark.color)
                    .frame(width: 8, height: 9)
                    .offset(y: -10)
            }
        }
        .overlay(EarShape().stroke(PetPalette.ink.opacity(0.22), lineWidth: 1))
        .rotationEffect(.degrees(tilt), anchor: .bottom)
    }

    private func torso(clock: TimeInterval) -> some View {
        ZStack {
            coatMarkings
                .frame(width: 66, height: 70)
                .clipShape(HeadShape())
                .overlay(HeadShape().stroke(PetPalette.ink.opacity(0.22), lineWidth: 1))
            face(clock: clock)
            if pose == .waiting {
                paw
                    .frame(width: 14, height: 14)
                    .offset(x: 28, y: -8)
            }
            if pose == .reminding {
                paw
                    .frame(width: 14, height: 14)
                    .offset(x: 30, y: reduceMotion ? -14 : -14 + sin(clock * 10) * 4)
            }
            if pose == .working {
                HStack(spacing: 20) {
                    paw.frame(width: 11, height: 11)
                    paw.frame(width: 11, height: 11)
                }
                .offset(y: 30)
            }
        }
    }

    private var coatMarkings: some View {
        ZStack {
            coat.base.color
            ForEach(Array(coat.patches.enumerated()), id: \.offset) { _, patch in
                Ellipse()
                    .fill(patch.dark ? coat.dark.color : coat.light.color)
                    .frame(width: CGFloat(patch.width), height: CGFloat(patch.height))
                    .rotationEffect(.degrees(patch.angle))
                    .offset(x: CGFloat(patch.centerX), y: CGFloat(patch.centerY))
            }
            BlazeShape()
                .fill(coat.white.color)
                .frame(width: 10 * CGFloat(coat.blazeScale), height: 22)
                .offset(x: CGFloat(coat.blazeOffset), y: -8)
            Ellipse()
                .fill(coat.white.color)
                .frame(width: 26, height: 30)
                .offset(y: 14)
        }
    }

    private var paw: some View {
        Circle()
            .fill(coat.white.color)
            .overlay(Circle().stroke(PetPalette.ink.opacity(0.25), lineWidth: 0.8))
    }

    private func face(clock: TimeInterval) -> some View {
        ZStack {
            if coat.showPoints {
                HStack(spacing: 16) {
                    Ellipse().fill(PetPalette.copper).frame(width: 5, height: 3)
                    Ellipse().fill(PetPalette.copper).frame(width: 5, height: 3)
                }
                .offset(y: -15)
                HStack(spacing: 25) {
                    Ellipse().fill(PetPalette.copper).frame(width: 6, height: 6)
                    Ellipse().fill(PetPalette.copper).frame(width: 6, height: 6)
                }
                .offset(y: 7)
            }
            eyes(clock: clock)
                .offset(y: -8)
            Ellipse()
                .fill(PetPalette.ink)
                .frame(width: 8, height: 6)
                .offset(y: 5)
            mouth
                .offset(y: 13)
        }
    }

    private func eyes(clock: TimeInterval) -> some View {
        let look: CGFloat = {
            guard pose == .thinking else { return 0 }
            return reduceMotion ? 3 : sin(clock * 1.2) * 3
        }()
        return HStack(spacing: 14) {
            eye(iris: coat.leftEye.color)
            eye(iris: coat.rightEye.color)
        }
        .offset(x: look)
    }

    private func eye(iris: Color) -> some View {
        Group {
            switch pose {
            case .resting:
                Capsule()
                    .fill(PetPalette.ink)
                    .frame(width: 10, height: 3)
            case .finished:
                ArcMouth()
                    .stroke(PetPalette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 9, height: 4)
                    .rotationEffect(.degrees(180))
            case .waiting, .reminding:
                openEye(iris: iris, size: 9)
            case .thinking, .working, nil:
                openEye(iris: iris, size: 8)
            }
        }
        .frame(width: 10, height: 10)
    }

    private func openEye(iris: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(iris)
            Circle().fill(PetPalette.ink).frame(width: size * 0.5, height: size * 0.5)
            Circle().fill(Color.white).frame(width: 2, height: 2).offset(x: size * 0.18, y: -size * 0.18)
        }
        .overlay(Circle().stroke(PetPalette.ink, lineWidth: 0.8))
        .frame(width: size, height: size)
    }

    private var mouth: some View {
        Group {
            switch pose {
            case .finished:
                ZStack {
                    Capsule()
                        .fill(PetPalette.tongue)
                        .frame(width: 6, height: 7)
                        .offset(y: 4)
                    ArcMouth()
                        .stroke(PetPalette.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .frame(width: 12, height: 5)
                }
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
}

private enum PetPalette {
    static let coat = Color(red: 0.97, green: 0.96, blue: 0.94)
    static let copper = Color(red: 0.80, green: 0.53, blue: 0.32)
    static let tongue = Color(red: 0.93, green: 0.47, blue: 0.52)
    static let ink = Color(red: 0.13, green: 0.14, blue: 0.17)
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

private struct HeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cheek = rect.minY + rect.height * 0.45
        let chin = rect.width * 0.2
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: cheek), control: CGPoint(x: rect.maxX - 4, y: rect.minY + 2))
        path.addQuadCurve(to: CGPoint(x: rect.midX + chin, y: rect.maxY - 2), control: CGPoint(x: rect.maxX - 2, y: rect.maxY - 10))
        path.addQuadCurve(to: CGPoint(x: rect.midX - chin, y: rect.maxY - 2), control: CGPoint(x: rect.midX, y: rect.maxY + 3))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: cheek), control: CGPoint(x: rect.minX + 2, y: rect.maxY - 10))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX + 4, y: rect.minY + 2))
        path.closeSubpath()
        return path
    }
}

private struct BlazeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let top = rect.width * 0.18
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.midX + top, y: rect.minY + top), control: CGPoint(x: rect.midX, y: rect.minY - top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX + top, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX - top, y: rect.minY + top), control: CGPoint(x: rect.midX - top, y: rect.midY))
        path.closeSubpath()
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
