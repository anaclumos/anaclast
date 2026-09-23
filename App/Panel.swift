import AppKit
import SwiftUI

@MainActor
@Observable
final class Island {
    var expanded = false
    var notch = CGSize(width: 185, height: 32)
}

struct IslandShape: Shape {
    static let ear: CGFloat = 12
    static let bottomRadius: CGFloat = 32
    static let overshoot: CGFloat = 32

    let size: CGSize

    func path(in bounds: CGRect) -> Path {
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.minY, width: size.width, height: size.height)
        let ear = Self.ear
        let radius = max(0, min(Self.bottomRadius, rect.height / 2, (rect.width - 2 * ear) / 2))
        let left = rect.minX + ear
        let right = rect.maxX - ear
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + ear), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - radius), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct IslandSurface<Content: View>: View {
    let island: Island
    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        IslandFrame(progress: island.expanded ? 1 : 0, notch: island.notch, size: size, content: content)
    }
}

// SwiftUI scale effects resize AppKit views, so a text field focused mid-spring keeps a line laid out at the shrunken size. A layer transform scales only the pixels. The nested host starts at its final size, because laying out from zero left stale blurred layers behind.
struct LayerScaled<Content: View>: NSViewRepresentable {
    let size: CGSize
    let scale: CGFloat
    let content: Content

    func makeCoordinator() -> NSHostingView<Content> {
        NSHostingView(rootView: content)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true
        context.coordinator.sizingOptions = []
        context.coordinator.frame = container.bounds
        context.coordinator.autoresizingMask = [.width, .height]
        container.addSubview(context.coordinator)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.rootView = content
        let pivot = CGPoint(x: size.width / 2, y: size.height)
        container.layer?.sublayerTransform = CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-pivot.x, -pivot.y, 0), CATransform3DMakeScale(scale, scale, 1)), CATransform3DMakeTranslation(pivot.x, pivot.y, 0))
    }
}

struct IslandFrame<Content: View>: View, Animatable {
    var progress: CGFloat
    let notch: CGSize
    let size: CGSize
    let content: Content

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let full = CGSize(width: size.width + 2 * IslandShape.ear, height: size.height + notch.height)
        let collapsed = CGSize(width: notch.width + 2 * IslandShape.ear, height: notch.height)
        let shape = IslandShape(size: CGSize(width: collapsed.width + (full.width - collapsed.width) * progress, height: collapsed.height + (full.height - collapsed.height) * progress))
        let rest = collapsed.width / full.width
        let scale = rest + (1 - rest) * progress
        let bounds = CGSize(width: full.width + 2 * IslandShape.overshoot, height: full.height + IslandShape.overshoot)
        let solid = min(1, (notch.height + 28) / full.height)
        ZStack(alignment: .top) {
            Color.clear
                .glassEffect(.regular, in: shape)
            shape
                .fill(LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: solid),
                    .init(color: .black.opacity(0.45), location: 0.55),
                    .init(color: .black.opacity(0.1), location: 1),
                ], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: full.height / bounds.height)))
            LayerScaled(size: CGSize(width: size.width, height: size.height + notch.height), scale: scale, content: content.frame(width: size.width, height: size.height).padding(.top, notch.height).blur(radius: max(0, 12 * (1 - progress))).opacity(progress).environment(\.colorScheme, .dark))
                .frame(width: size.width, height: size.height + notch.height)
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .top)
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
final class FloatingPanel: NSPanel {
    private let island = Island()
    private let size: CGSize
    var onHide: () -> Void = {}

    init<Content: View>(size: CGSize, @ViewBuilder content: () -> Content) {
        self.size = size
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless], backing: .buffered, defer: true)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        let hosting = NSHostingView(rootView: IslandSurface(island: island, size: size, content: content))
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func resignKey() {
        super.resignKey()
        hide()
    }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        island.notch = Self.notch(on: screen)
        let width = size.width + 2 * IslandShape.ear + 2 * IslandShape.overshoot
        let height = size.height + island.notch.height + IslandShape.overshoot
        setFrame(CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height), display: false)
        makeKeyAndOrderFront(nil)
        withAnimation(.spring(duration: 0.5, bounce: 0.35)) { island.expanded = true }
    }

    func hide() {
        guard isVisible, island.expanded else { return }
        onHide()
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
            island.expanded = false
        } completion: { [weak self] in
            guard let self, !island.expanded else { return }
            orderOut(nil)
        }
    }

    var isShown: Bool { isVisible && island.expanded }

    func toggle() {
        isShown ? hide() : show()
    }

    private static func notch(on screen: NSScreen) -> CGSize {
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return CGSize(width: 185, height: max(menuBar, 24))
        }
        return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
    }
}
