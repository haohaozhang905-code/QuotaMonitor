import AppKit
import SwiftUI
import XCTest
@testable import QuotaMonitor

final class PanelHelpPopoverTests: XCTestCase {
    @MainActor func testHelpUsesBorderlessCustomShadowWithoutWindowChromeOrAnimation() {
        let coordinator = PanelHelpPopover<Text>.Coordinator()
        XCTAssertFalse(coordinator.panel.hasShadow)
        XCTAssertEqual(coordinator.panel.animationBehavior, .none)
        XCTAssertFalse(coordinator.panel.styleMask.contains(.titled))
        XCTAssertTrue(coordinator.panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertNil(coordinator.panel.contentViewController, "Closed help should not create its content tree")
        coordinator.invalidate()
    }

    @MainActor func testUnattachedAnchorCannotOpenAndCancelledPresentationCannotReappear() async {
        var showing = true
        let binding = Binding(get: { showing }, set: { showing = $0 })
        let coordinator = PanelHelpPopover<Text>.Coordinator()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        coordinator.update(isPresented: binding, anchor: anchor, arrowEdge: .trailing, content: AnyView(Text("Help")))
        await Task.yield()
        XCTAssertFalse(coordinator.panel.isVisible)
        XCTAssertNil(coordinator.panel.contentViewController)
        coordinator.invalidate()
        await Task.yield()
        XCTAssertFalse(coordinator.panel.isVisible)
    }

    @MainActor func testWindowPresentationUpdatesDismissesAndCleansUp() async throws {
        guard ProcessInfo.processInfo.environment["QMT_HELP_WINDOW_TESTS"] == "1" else {
            throw XCTSkip("Opt in on a macOS desktop to verify native window lifecycle")
        }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 240, y: 140, width: 18, height: 18))
        try XCTUnwrap(window.contentView).addSubview(anchor)
        window.orderFront(nil)
        let coordinator = PanelHelpPopover<Text>.Coordinator()
        defer { coordinator.invalidate(); window.close() }
        var showing = true
        let binding = Binding(get: { showing }, set: { showing = $0 })
        coordinator.update(isPresented: binding, anchor: anchor, arrowEdge: .trailing,
                           content: AnyView(Text("Short help").padding(12).frame(width: 250)))
        await Task.yield()
        XCTAssertTrue(coordinator.panel.isVisible)
        XCTAssertTrue(coordinator.panel.parent === window)
        let visibleBounds = window.convertToScreen(window.contentLayoutRect)
        XCTAssertTrue(visibleBounds.contains(coordinator.panel.frame), "Help must stay inside the parent window")
        let controller = try XCTUnwrap(coordinator.panel.contentViewController)
        coordinator.update(isPresented: binding, anchor: anchor, arrowEdge: .trailing,
                           content: AnyView(Text("Updated explanation").padding(12).frame(width: 250)))
        await Task.yield()
        XCTAssertTrue(controller === coordinator.panel.contentViewController)
        coordinator.dismiss()
        XCTAssertFalse(showing, "Native dismissal must clear SwiftUI state so the next click reopens")
        showing = true
        coordinator.update(isPresented: binding, anchor: anchor, arrowEdge: .top, content: AnyView(Text("Reopened")))
        await Task.yield()
        XCTAssertTrue(coordinator.panel.isVisible)
        coordinator.invalidate()
        XCTAssertFalse(coordinator.panel.isVisible, "Removing the trigger must not leave an orphan popover")
    }
}
