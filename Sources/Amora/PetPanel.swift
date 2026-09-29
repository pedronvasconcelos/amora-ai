import AppKit
import SwiftUI

enum PetMetrics {
    static let size = CGSize(width: 104, height: 128)
    /// Codex sizes a floating pet by width from 80 to 224 points, with 112 as the default.
    static let minimumScale: CGFloat = 80.0 / 112.0
    static let maximumScale: CGFloat = 224.0 / 112.0
    static let defaultScale: CGFloat = 1
    /// Share of the shorter side that grabs a resize. A fixed pixel edge is easy to miss on a borderless pet.
    static let resizeMarginFraction: CGFloat = 0.3
    /// Session companions beside one pet. Further sessions still appear in the menu.
    static let maximumCompanions = 8
    /// A subagent's pet is a pup: this share of its pet's size.
    static let subagentScale: CGFloat = 0.75

    static func size(for scale: CGFloat) -> CGSize {
        let resolved = clampedPetScale(scale)
        return CGSize(width: size.width * resolved, height: size.height * resolved)
    }
}

func clampedPetScale(_ scale: CGFloat) -> CGFloat {
    guard scale.isFinite else { return PetMetrics.defaultScale }
    return min(max(scale, PetMetrics.minimumScale), PetMetrics.maximumScale)
}

enum PetResizeEdge: Equatable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
}

func petResizeMargin(for size: CGSize) -> CGFloat {
    let shorter = min(size.width, size.height)
    guard shorter > 1 else { return 0 }
    return shorter * PetMetrics.resizeMarginFraction
}

func petResizeRegions(in size: CGSize) -> [(CGRect, PetResizeEdge)] {
    let margin = petResizeMargin(for: size)
    guard size.width > margin * 2, size.height > margin * 2 else { return [] }
    let width = size.width
    let height = size.height
    return [
        (CGRect(x: 0, y: height - margin, width: margin, height: margin), .topLeft),
        (CGRect(x: width - margin, y: height - margin, width: margin, height: margin), .topRight),
        (CGRect(x: 0, y: 0, width: margin, height: margin), .bottomLeft),
        (CGRect(x: width - margin, y: 0, width: margin, height: margin), .bottomRight),
        (CGRect(x: margin, y: height - margin, width: width - margin * 2, height: margin), .top),
        (CGRect(x: margin, y: 0, width: width - margin * 2, height: margin), .bottom),
        (CGRect(x: 0, y: margin, width: margin, height: height - margin * 2), .left),
        (CGRect(x: width - margin, y: margin, width: margin, height: height - margin * 2), .right),
    ]
}

func petResizeEdge(at point: CGPoint, in size: CGSize) -> PetResizeEdge? {
    petResizeRegions(in: size).first { $0.0.contains(point) }?.1
}

func resizedPetFrame(
    initialFrame: CGRect,
    edge: PetResizeEdge,
    initialMouse: CGPoint,
    mouse: CGPoint,
    screenFrame: CGRect
) -> CGRect {
    let anchor = petResizeAnchor(for: initialFrame, edge: edge)
    let moving = petResizeMovingPoint(for: initialFrame, edge: edge)
    let vx = moving.x - anchor.x
    let vy = moving.y - anchor.y
    let lengthSquared = vx * vx + vy * vy
    guard lengthSquared > 1, initialFrame.width > 1 else { return initialFrame }
    let start = ((initialMouse.x - anchor.x) * vx + (initialMouse.y - anchor.y) * vy) / lengthSquared
    let current = ((mouse.x - anchor.x) * vx + (mouse.y - anchor.y) * vy) / lengthSquared
    let factor = abs(start) > 0.05 ? current / start : 1
    let scale = clampedPetScale(initialFrame.width * factor / PetMetrics.size.width)
    return petFrame(scale: scale, anchor: anchor, edge: edge, screenFrame: screenFrame)
}

private func petResizeAnchor(for frame: CGRect, edge: PetResizeEdge) -> CGPoint {
    switch edge {
    case .right: CGPoint(x: frame.minX, y: frame.midY)
    case .left: CGPoint(x: frame.maxX, y: frame.midY)
    case .top: CGPoint(x: frame.midX, y: frame.minY)
    case .bottom: CGPoint(x: frame.midX, y: frame.maxY)
    case .topRight: CGPoint(x: frame.minX, y: frame.minY)
    case .topLeft: CGPoint(x: frame.maxX, y: frame.minY)
    case .bottomRight: CGPoint(x: frame.minX, y: frame.maxY)
    case .bottomLeft: CGPoint(x: frame.maxX, y: frame.maxY)
    }
}

private func petResizeMovingPoint(for frame: CGRect, edge: PetResizeEdge) -> CGPoint {
    switch edge {
    case .right: CGPoint(x: frame.maxX, y: frame.midY)
    case .left: CGPoint(x: frame.minX, y: frame.midY)
    case .top: CGPoint(x: frame.midX, y: frame.maxY)
    case .bottom: CGPoint(x: frame.midX, y: frame.minY)
    case .topRight: CGPoint(x: frame.maxX, y: frame.maxY)
    case .topLeft: CGPoint(x: frame.minX, y: frame.maxY)
    case .bottomRight: CGPoint(x: frame.maxX, y: frame.minY)
    case .bottomLeft: CGPoint(x: frame.minX, y: frame.minY)
    }
}

private func anchoredPetFrame(size: CGSize, anchor: CGPoint, edge: PetResizeEdge) -> CGRect {
    switch edge {
    case .right:
        CGRect(x: anchor.x, y: anchor.y - size.height / 2, width: size.width, height: size.height)
    case .left:
        CGRect(x: anchor.x - size.width, y: anchor.y - size.height / 2, width: size.width, height: size.height)
    case .top:
        CGRect(x: anchor.x - size.width / 2, y: anchor.y, width: size.width, height: size.height)
    case .bottom:
        CGRect(x: anchor.x - size.width / 2, y: anchor.y - size.height, width: size.width, height: size.height)
    case .topRight:
        CGRect(x: anchor.x, y: anchor.y, width: size.width, height: size.height)
    case .topLeft:
        CGRect(x: anchor.x - size.width, y: anchor.y, width: size.width, height: size.height)
    case .bottomRight:
        CGRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
    case .bottomLeft:
        CGRect(x: anchor.x - size.width, y: anchor.y - size.height, width: size.width, height: size.height)
    }
}

private func petFrameFits(_ frame: CGRect, in screen: CGRect) -> Bool {
    frame.minX >= screen.minX - 0.01
        && frame.minY >= screen.minY - 0.01
        && frame.maxX <= screen.maxX + 0.01
        && frame.maxY <= screen.maxY + 0.01
}

private func petFrame(scale: CGFloat, anchor: CGPoint, edge: PetResizeEdge, screenFrame: CGRect) -> CGRect {
    let high = clampedPetScale(scale)
    func frame(_ scale: CGFloat) -> CGRect {
        anchoredPetFrame(size: PetMetrics.size(for: scale), anchor: anchor, edge: edge)
    }
    if !petFrameFits(frame(PetMetrics.minimumScale), in: screenFrame) {
        let raw = frame(PetMetrics.minimumScale)
        let origin = clampedPetOrigin(raw.origin, windowSize: raw.size, screenFrame: screenFrame)
        return CGRect(origin: origin, size: raw.size)
    }
    if petFrameFits(frame(high), in: screenFrame) {
        return frame(high)
    }
    var low = PetMetrics.minimumScale
    var upper = high
    for _ in 0..<20 {
        let mid = (low + upper) / 2
        if petFrameFits(frame(mid), in: screenFrame) {
            low = mid
        } else {
            upper = mid
        }
    }
    return frame(low)
}

enum PetPanelPolicy {
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let level: NSWindow.Level = .floating
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle
    ]
}

func defaultPetOrigin(windowSize: CGSize, screenFrame: CGRect) -> CGPoint {
    CGPoint(
        x: screenFrame.maxX - windowSize.width - 28,
        y: screenFrame.minY + 28
    )
}

func clampedPetOrigin(_ origin: CGPoint, windowSize: CGSize, screenFrame: CGRect) -> CGPoint {
    let maxX = max(screenFrame.minX, screenFrame.maxX - windowSize.width)
    let maxY = max(screenFrame.minY, screenFrame.maxY - windowSize.height)
    return CGPoint(
        x: min(max(origin.x, screenFrame.minX), maxX),
        y: min(max(origin.y, screenFrame.minY), maxY)
    )
}

/// Where a pet's session companions sit: a row beside the pet on the side with more room, bottoms level
/// with the pet, wrapping to further rows above (or below, near the top of the screen) when the row runs out.
func companionFrames(petFrame: CGRect, sizes: [CGSize], screenFrame: CGRect) -> [CGRect] {
    let leftward = petFrame.midX - screenFrame.minX >= screenFrame.maxX - petFrame.midX
    let upward = screenFrame.maxY - petFrame.maxY >= petFrame.minY - screenFrame.minY
    var frames: [CGRect] = []
    var edge = leftward ? petFrame.minX : petFrame.maxX
    var baseline = petFrame.minY
    var placedInRow = 0
    for size in sizes {
        var x = leftward ? edge - size.width : edge
        let overflows = leftward ? x < screenFrame.minX : x + size.width > screenFrame.maxX
        if overflows, placedInRow > 0 {
            baseline += upward ? petFrame.height : -petFrame.height
            edge = leftward ? petFrame.maxX : petFrame.minX
            x = leftward ? edge - size.width : edge
            placedInRow = 0
        }
        let origin = clampedPetOrigin(CGPoint(x: x, y: baseline), windowSize: size, screenFrame: screenFrame)
        frames.append(CGRect(origin: origin, size: size))
        edge = leftward ? x : x + size.width
        placedInRow += 1
    }
    return frames
}

final class PetPanelWindow: NSPanel {
    var hostsMenu = false
    override var canBecomeKey: Bool { hostsMenu }
    override var canBecomeMain: Bool { false }
}

@MainActor
private func makePetPanel(size: CGSize, content: some View) -> (PetPanelWindow, PetDragView) {
    let window = PetPanelWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: PetPanelPolicy.styleMask,
        backing: .buffered,
        defer: false
    )
    window.level = PetPanelPolicy.level
    window.collectionBehavior = PetPanelPolicy.collectionBehavior
    window.hidesOnDeactivate = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.becomesKeyOnlyIfNeeded = true
    window.acceptsMouseMovedEvents = true
    let host = NSHostingView(rootView: content)
    host.sizingOptions = []
    host.frame = NSRect(origin: .zero, size: size)
    host.autoresizingMask = [.width, .height]
    host.wantsLayer = true
    host.layer?.backgroundColor = NSColor.clear.cgColor
    let drag = PetDragView(frame: host.frame)
    drag.autoresizingMask = [.width, .height]
    let container = NSView(frame: host.frame)
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.clear.cgColor
    container.addSubview(host)
    container.addSubview(drag)
    window.contentView = container
    window.setContentSize(size)
    return (window, drag)
}

@MainActor
final class PetPanelController: NSObject, NSWindowDelegate {
    let window: PetPanelWindow
    private let petID: UUID
    private let preferences: PetPreferences
    private let onSelect: () -> Void
    private var acceptsOriginUpdates = false

    init(petID: UUID, preferences: PetPreferences, content: some View, onSelect: @escaping () -> Void = {}) {
        self.petID = petID
        self.preferences = preferences
        self.onSelect = onSelect
        let (window, drag) = makePetPanel(size: PetMetrics.size(for: preferences.scale(for: petID)), content: content)
        self.window = window
        super.init()
        window.delegate = self
        drag.onMove = { [weak self] origin in
            guard let self else { return }
            self.preferences.setOrigin(origin, for: self.petID)
        }
        drag.onResize = { [weak self] scale, origin in
            guard let self else { return }
            self.preferences.setPlacement(origin: origin, scale: scale, for: self.petID)
        }
        drag.onSelect = { [weak self] in
            self?.onSelect()
        }
    }

    func place(on screenFrame: CGRect) {
        let size = PetMetrics.size(for: preferences.scale(for: petID))
        let saved = preferences.origin(for: petID) ?? defaultPetOrigin(windowSize: size, screenFrame: screenFrame)
        let origin = clampedPetOrigin(saved, windowSize: size, screenFrame: screenFrame)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        acceptsOriginUpdates = true
    }

    func show() {
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        place(on: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900))
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    var menuAnchorView: NSView {
        window.contentView!
    }

    func setHostsMenu(_ hosts: Bool) {
        window.hostsMenu = hosts
        if hosts {
            window.makeKeyAndOrderFront(nil)
        } else if window.isKeyWindow {
            window.resignKey()
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard acceptsOriginUpdates else { return }
        preferences.setOrigin(window.frame.origin, for: petID)
    }
}

/// A session companion's window. It sits beside its pet and cannot be resized;
/// dragging it moves the pet, and the whole pack follows.
@MainActor
final class CompanionPanelController {
    let window: PetPanelWindow

    init(size: CGSize, pet: NSWindow, content: some View, onSelect: @escaping () -> Void = {}) {
        let (window, drag) = makePetPanel(size: size, content: content)
        drag.allowsResize = false
        drag.movingWindow = pet
        drag.onSelect = onSelect
        self.window = window
    }

    func setFrame(_ frame: CGRect) {
        guard window.frame != frame else { return }
        window.setFrame(frame, display: window.isVisible)
    }

    func show() {
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    var menuAnchorView: NSView {
        window.contentView!
    }

    func setHostsMenu(_ hosts: Bool) {
        window.hostsMenu = hosts
        if hosts {
            window.makeKeyAndOrderFront(nil)
        } else if window.isKeyWindow {
            window.resignKey()
        }
    }
}

private final class PetDragView: NSView {
    var onMove: ((CGPoint) -> Void)?
    var onResize: ((CGFloat, CGPoint) -> Void)?
    var onSelect: (() -> Void)?
    var allowsResize = true
    /// The window a drag moves, when it is not this view's own.
    weak var movingWindow: NSWindow?

    private enum Gesture {
        case move(origin: NSPoint, mouse: NSPoint)
        case resize(frame: CGRect, mouse: NSPoint, edge: PetResizeEdge)
    }

    private let borderLayer = CAShapeLayer()
    private var gesture: Gesture?
    private var moved = false
    private var hovering = false
    private var pushedCursor = false

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1.5
        borderLayer.strokeColor = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 0.35).cgColor
        borderLayer.isHidden = true
        layer?.addSublayer(borderLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let scale = bounds.width / PetMetrics.size.width
        let inset = 8 * scale
        let radius = 20 * scale
        let rect = bounds.insetBy(dx: inset, dy: inset)
        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard allowsResize else {
            addCursorRect(bounds, cursor: .openHand)
            return
        }
        for (rect, edge) in petResizeRegions(in: bounds.size) {
            addCursorRect(rect, cursor: petResizeCursor(for: edge))
        }
        let margin = petResizeMargin(for: bounds.size)
        let interior = bounds.insetBy(dx: margin, dy: margin)
        if interior.width > 0, interior.height > 0 {
            addCursorRect(interior, cursor: .openHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        borderLayer.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        if case .resize = gesture { return }
        borderLayer.isHidden = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        moved = false
        borderLayer.isHidden = false
        let mouse = NSEvent.mouseLocation
        let point = convert(event.locationInWindow, from: nil)
        if allowsResize, let edge = petResizeEdge(at: point, in: bounds.size) {
            gesture = .resize(frame: window.frame, mouse: mouse, edge: edge)
            push(petResizeCursor(for: edge))
        } else {
            gesture = .move(origin: (movingWindow ?? window).frame.origin, mouse: mouse)
            push(.closedHand)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let gesture else { return }
        let mouse = NSEvent.mouseLocation
        switch gesture {
        case .move(let origin, let start):
            if hypot(mouse.x - start.x, mouse.y - start.y) > 2 {
                moved = true
            }
            let next = NSPoint(x: origin.x + (mouse.x - start.x), y: origin.y + (mouse.y - start.y))
            (movingWindow ?? window).setFrameOrigin(next)
            onMove?(next)
        case .resize(let frame, let start, let edge):
            if hypot(mouse.x - start.x, mouse.y - start.y) > 2 {
                moved = true
            }
            let screen = screenFrame(containing: mouse, window: window)
            let next = resizedPetFrame(
                initialFrame: frame,
                edge: edge,
                initialMouse: start,
                mouse: mouse,
                screenFrame: screen
            )
            window.setFrame(next, display: true)
            onResize?(next.width / PetMetrics.size.width, next.origin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let shouldSelect = gesture != nil && !moved
        gesture = nil
        moved = false
        popCursor()
        borderLayer.isHidden = !hovering && !pointerIsInside
        if shouldSelect {
            onSelect?()
        }
    }

    private var pointerIsInside: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func push(_ cursor: NSCursor) {
        cursor.push()
        pushedCursor = true
    }

    private func popCursor() {
        guard pushedCursor else { return }
        NSCursor.pop()
        pushedCursor = false
    }

    private func screenFrame(containing mouse: CGPoint, window: NSWindow) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? window.screen ?? NSScreen.main
        return screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

private func petResizeCursor(for edge: PetResizeEdge) -> NSCursor {
    if #available(macOS 15, *) {
        return NSCursor.frameResize(position: edge.resizePosition, directions: .all)
    }
    switch edge {
    case .left, .right, .topLeft, .bottomRight:
        return .resizeLeftRight
    case .top, .bottom, .topRight, .bottomLeft:
        return .resizeUpDown
    }
}

@available(macOS 15, *)
private extension PetResizeEdge {
    var resizePosition: NSCursor.FrameResizePosition {
        switch self {
        case .top: .top
        case .left: .left
        case .bottom: .bottom
        case .right: .right
        case .topLeft: .topLeft
        case .topRight: .topRight
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        }
    }
}
