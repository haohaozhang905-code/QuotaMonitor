import AppKit
import SwiftUI

/// A quiet explanation surface shared by all question-mark buttons.
struct PanelHelpButton<Label: View, Content: View>: View {
    @Binding var isPresented: Bool
    let width: CGFloat
    var arrowEdge: Edge = .top
    let accessibilityLabel: String
    var accessibilityValue: String? = nil
    var accessibilityHint: String? = nil
    @ViewBuilder let label: () -> Label
    @ViewBuilder let content: () -> Content
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            isFocused = true
            isPresented.toggle()
        } label: {
            label()
                .frame(minWidth: 18, minHeight: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.space, .return]) { _ in
            isPresented.toggle()
            return .handled
        }
        .onKeyPress(.escape) {
            guard isPresented else { return .ignored }
            isPresented = false
            return .handled
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
        .accessibilityHint(accessibilityHint ?? "")
        .background {
            PanelHelpPopover(isPresented: $isPresented, arrowEdge: arrowEdge) {
                content()
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(width: width, alignment: .leading)
                    .environment(\.colorScheme, colorScheme)
                    .environment(\.locale, locale)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onDisappear { isPresented = false }
    }
}

/// A borderless child panel avoids system material, border and shadow chrome.
struct PanelHelpPopover<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let arrowEdge: Edge
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(
            isPresented: $isPresented, anchor: view, arrowEdge: arrowEdge,
            content: AnyView(content())
        )
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    @MainActor final class Coordinator: NSObject {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        private var presentation: Binding<Bool>?
        private var presentationTask: Task<Void, Never>?
        private var hosting: NSHostingController<AnyView>?
        private weak var parentWindow: NSWindow?
        private weak var anchor: NSView?
        private var eventMonitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var content = AnyView(EmptyView())
        private var arrowEdge: Edge = .top

        override init() {
            super.init()
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = true
            panel.animationBehavior = .none
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = true
        }

        func update(isPresented: Binding<Bool>, anchor: NSView, arrowEdge: Edge, content: AnyView) {
            presentation = isPresented
            presentationTask?.cancel()
            guard isPresented.wrappedValue else {
                hide()
                return
            }
            self.content = content
            self.arrowEdge = arrowEdge
            self.anchor = anchor
            presentationTask = Task { @MainActor [weak self, weak anchor] in
                guard !Task.isCancelled, let self, let anchor,
                      let window = anchor.window, self.presentation?.wrappedValue == true else { return }
                self.show(in: window, anchor: anchor)
            }
        }

        private func show(in window: NSWindow, anchor: NSView) {
            let initial = AnyView(HelpBubble(edge: arrowEdge, arrowOffset: 100, content: content))
            if hosting == nil {
                let hosting = NSHostingController(rootView: initial)
                self.hosting = hosting
                panel.contentViewController = hosting
            } else {
                hosting?.rootView = initial
            }
            guard let hosting else { return }
            let size = hosting.view.fittingSize
            guard size.width > 0, size.height > 0 else { return }
            let anchorRect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            var bounds = window.convertToScreen(window.contentLayoutRect).insetBy(dx: 10, dy: 10)
            if let screen = window.screen { bounds = bounds.intersection(screen.visibleFrame.insetBy(dx: 6, dy: 6)) }
            var edge = arrowEdge
            let shadowInset: CGFloat = 8
            var origin = CGPoint(x: anchorRect.midX - size.width / 2,
                                 y: anchorRect.minY - size.height + shadowInset - 4)
            if edge == .trailing {
                origin = CGPoint(x: anchorRect.minX - size.width + shadowInset - 4,
                                 y: anchorRect.midY - size.height / 2)
            } else if origin.y < bounds.minY {
                edge = .bottom
                origin.y = anchorRect.maxY - shadowInset + 4
            }
            origin.x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
            origin.y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
            let arrowOffset = edge == .trailing ? size.height - (anchorRect.midY - origin.y) : anchorRect.midX - origin.x
            hosting.rootView = AnyView(HelpBubble(edge: edge, arrowOffset: arrowOffset, content: content))
            panel.appearance = window.effectiveAppearance
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
            if !panel.isVisible {
                parentWindow = window
                window.addChildWindow(panel, ordered: .above)
                panel.orderFront(nil)
                installDismissal(in: window)
            }
        }

        private func installDismissal(in window: NSWindow) {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, self.panel.isVisible else { return false }
                    if event.type == .keyDown {
                        guard event.keyCode == 53,
                              event.window === self.parentWindow || event.window === self.panel else { return false }
                        self.dismiss()
                        return true
                    }
                    if event.type == .scrollWheel {
                        if event.window === self.parentWindow { self.dismiss() }
                        return false
                    }
                    if event.window === self.panel { return false }
                    // Let the trigger toggle itself on mouse-up, preventing an
                    // outside dismissal followed by an unintended reopen.
                    if event.window === self.parentWindow, let anchor = self.anchor {
                        let point = anchor.convert(event.locationInWindow, from: nil)
                        if anchor.bounds.contains(point) { return false }
                    }
                    self.dismiss()
                    return false
                }
                return consumed ? nil : event
            }
            for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification,
                         NSWindow.willMoveNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismiss() }
                })
            }
        }

        func dismiss() {
            hide()
            presentation?.wrappedValue = false
        }

        private func hide() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            parentWindow?.removeChildWindow(panel)
            panel.orderOut(nil)
            parentWindow = nil
        }

        func invalidate() {
            presentationTask?.cancel()
            presentationTask = nil
            presentation = nil
            hide()
            panel.contentViewController = nil
            hosting = nil
        }
    }
}

struct HelpBubble: View {
    let edge: Edge
    let arrowOffset: CGFloat
    let content: AnyView
    @Environment(\.colorScheme) private var colorScheme

    private let shadowInset: CGFloat = 8

    var body: some View {
        ZStack {
            HelpBubbleShape(edge: edge, arrowOffset: adjustedArrowOffset)
                .fill(PanelTheme.helpSurface)
                .overlay {
                    HelpBubbleShape(edge: edge, arrowOffset: adjustedArrowOffset)
                        .stroke(PanelTheme.helpBorder, lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10),
                        radius: 5, x: 0, y: 2)
            content
                .padding(edge == .trailing ? Edge.Set.trailing : edge == .bottom ? Edge.Set.bottom : Edge.Set.top, 6)
        }
        .padding(shadowInset)
    }

    private var adjustedArrowOffset: CGFloat {
        arrowOffset - shadowInset
    }
}

/// One outline for the body and arrow, with no overlapping strokes or seams.
struct HelpBubbleShape: Shape {
    let edge: Edge
    let arrowOffset: CGFloat

    func path(in rect: CGRect) -> Path {
        let trailing = edge == .trailing
        let width = trailing ? rect.height : rect.width
        let height = trailing ? rect.width : rect.height
        let r = PanelTheme.tooltipCornerRadius, depth: CGFloat = 6
        let tip = min(max(arrowOffset, r + 8), width - r - 8)
        var path = Path()
        path.move(to: CGPoint(x: r, y: depth))
        path.addLine(to: CGPoint(x: tip - 7, y: depth))
        path.addLine(to: CGPoint(x: tip, y: 0))
        path.addLine(to: CGPoint(x: tip + 7, y: depth))
        path.addLine(to: CGPoint(x: width - r, y: depth))
        path.addQuadCurve(to: CGPoint(x: width, y: depth + r), control: CGPoint(x: width, y: depth))
        path.addLine(to: CGPoint(x: width, y: height - r))
        path.addQuadCurve(to: CGPoint(x: width - r, y: height), control: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: r, y: height))
        path.addQuadCurve(to: CGPoint(x: 0, y: height - r), control: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: depth + r))
        path.addQuadCurve(to: CGPoint(x: r, y: depth), control: CGPoint(x: 0, y: depth))
        path.closeSubpath()
        if trailing { return path.applying(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.width, ty: 0)) }
        if edge == .bottom { return path.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.height)) }
        return path
    }
}
