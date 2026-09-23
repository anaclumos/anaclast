import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class IslandActivity {
    var visible = false
    var notch = CGSize(width: 185, height: 32)
}

@MainActor
final class NowPlayingIsland {
    private let panel: NSPanel
    private let activity = IslandActivity()
    private let media: NowPlayingMonitor
    private var observer: NSObjectProtocol?
    var suppressed = false {
        didSet { update() }
    }

    init(media: NowPlayingMonitor) {
        self.media = media
        panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        let hosting = NSHostingView(rootView: NowPlayingActivityView(activity: activity, media: media))
        hosting.sizingOptions = []
        panel.contentView = hosting
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.activity.visible { self.place() }
                self.update()
            }
        }
    }

    // The island belongs to the notch. On a screen without one it would sit on top of menu bar items.
    private static var notchedScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    func update() {
        let active = !suppressed && media.state.isPlaying && Self.notchedScreen != nil
        guard active != activity.visible else { return }
        if active {
            place()
            panel.orderFrontRegardless()
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { activity.visible = true }
        } else {
            withAnimation(.spring(duration: 0.3, bounce: 0)) {
                activity.visible = false
            } completion: { [weak self] in
                guard let self, !activity.visible else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func place() {
        guard let screen = Self.notchedScreen else { return }
        activity.notch = FloatingPanel.notch(on: screen)
        let width = activity.notch.width + 2 * (activity.notch.height + IslandShape.ear)
        panel.setFrame(CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - activity.notch.height, width: width, height: activity.notch.height), display: false)
    }
}

private struct NowPlayingActivityView: View {
    let activity: IslandActivity
    let media: NowPlayingMonitor

    var body: some View {
        let notch = activity.notch
        let wing = notch.height
        ActivityFrame(progress: activity.visible ? 1 : 0, notch: notch, content: HStack(spacing: 0) {
            ActivityArtwork(image: media.artwork)
                .frame(width: wing - 10, height: wing - 10)
                .clipShape(.rect(cornerRadius: 6))
                .frame(width: wing)
            Color.clear
                .frame(width: notch.width)
            Soundwave(tint: media.tint)
                .frame(width: 18, height: wing - 14)
                .frame(width: wing)
        })
    }
}

private struct ActivityFrame<Content: View>: View, Animatable {
    var progress: CGFloat
    let notch: CGSize
    let content: Content

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let shape = IslandShape(size: CGSize(width: notch.width + 2 * notch.height * progress + 2 * IslandShape.ear, height: notch.height))
        ZStack(alignment: .top) {
            shape.fill(.black)
            content
                .frame(height: notch.height)
                .opacity(progress)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(shape)
    }
}

private struct ActivityArtwork: View {
    let image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(.white.opacity(0.12))
                .overlay(Image(systemName: "music.note").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)))
        }
    }
}

// The bars are decorative, since real levels would need an audio capture grant. They run as Core Animation in the render server, so playing costs the app no per-frame work.
private struct Soundwave: NSViewRepresentable {
    let tint: NSColor

    func makeNSView(context: Context) -> SoundwaveView {
        SoundwaveView(frame: .zero)
    }

    func updateNSView(_ view: SoundwaveView, context: Context) {
        view.tint = tint
    }
}

private final class SoundwaveView: NSView {
    private let bars = (0..<4).map { _ in CALayer() }
    private var observer: NSObjectProtocol?
    var tint = NSColor.white {
        didSet { bars.forEach { $0.backgroundColor = tint.cgColor } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = 1.5
            bar.backgroundColor = tint.cgColor
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    // AppKit drops sublayer animations when the panel is ordered in, so the bars restart each time the window becomes visible.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        guard let window else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window?.occlusionState.contains(.visible) == true else { return }
                self.animate()
            }
        }
    }

    private func animate() {
        for (index, bar) in bars.enumerated() where bar.animation(forKey: "pulse") == nil {
            let pulse = CABasicAnimation(keyPath: "transform.scale.y")
            pulse.fromValue = 0.3
            pulse.toValue = 1
            pulse.duration = [0.42, 0.55, 0.36, 0.48][index]
            pulse.timeOffset = Double(index) * 0.17
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(pulse, forKey: "pulse")
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.frame = CGRect(x: CGFloat(index) * 5, y: 0, width: 3, height: bounds.height)
        }
        CATransaction.commit()
    }
}
