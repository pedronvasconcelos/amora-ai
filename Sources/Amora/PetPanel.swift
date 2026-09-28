import AppKit
import SwiftUI

enum PetMetrics {
    static let size = CGSize(width: 104, height: 128)
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

final class PetPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetPanelController: NSObject, NSWindowDelegate {
    let window: PetPanelWindow
    private let preferences: PetPreferences
    private var acceptsOriginUpdates = false

    init(preferences: PetPreferences, content: some View) {
        self.preferences = preferences
        let window = PetPanelWindow(
            contentRect: NSRect(origin: .zero, size: PetMetrics.size),
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
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: PetMetrics.size)
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
        window.setContentSize(PetMetrics.size)
        self.window = window
        super.init()
        window.delegate = self
        drag.onMove = { [weak self] origin in
            self?.preferences.setOrigin(origin)
        }
    }

    func place(on screenFrame: CGRect) {
        let size = window.frame.size
        let saved = preferences.origin ?? defaultPetOrigin(windowSize: size, screenFrame: screenFrame)
        window.setFrameOrigin(clampedPetOrigin(saved, windowSize: size, screenFrame: screenFrame))
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

    func windowDidMove(_ notification: Notification) {
        guard acceptsOriginUpdates else { return }
        preferences.setOrigin(window.frame.origin)
    }
}

private final class PetDragView: NSView {
    var onMove: ((CGPoint) -> Void)?
    private var anchor: (origin: NSPoint, mouse: NSPoint)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        anchor = (window.frame.origin, NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let anchor else { return }
        let mouse = NSEvent.mouseLocation
        let origin = NSPoint(
            x: anchor.origin.x + (mouse.x - anchor.mouse.x),
            y: anchor.origin.y + (mouse.y - anchor.mouse.y)
        )
        window.setFrameOrigin(origin)
        onMove?(origin)
    }

    override func mouseUp(with event: NSEvent) {
        anchor = nil
    }
}
