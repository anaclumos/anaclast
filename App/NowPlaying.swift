import AppKit
import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI

struct NowPlaying: Equatable {
    let title: String
    let artist: String?
    var playing: Bool
    let artwork: Data?
}

enum NowPlayingState: Equatable {
    case missing
    case idle
    case media(NowPlaying)

    var isPlaying: Bool {
        if case .media(let media) = self { media.playing } else { false }
    }

    var artwork: Data? {
        if case .media(let media) = self { media.artwork } else { nil }
    }
}

private struct StreamEvent: Decodable {
    struct Payload: Decodable {
        let title: String?
        let artist: String?
        let playing: Bool?
        let artworkData: String?
    }

    let payload: Payload
}

private struct Tint: Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

@MainActor
@Observable
final class NowPlayingMonitor {
    private(set) var state = NowPlayingState.idle
    private(set) var artwork: NSImage?
    private(set) var tint = NSColor.white
    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var running = false

    nonisolated static let mediaControl = URL(filePath: "/opt/homebrew/bin/media-control")

    func start() {
        running = true
        guard FileManager.default.isExecutableFile(atPath: Self.mediaControl.path) else {
            publish(.missing, tint: nil)
            return
        }
        let process = Process()
        process.executableURL = Self.mediaControl
        process.arguments = ["stream", "--no-diff", "--debounce=200"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] ended in
            log.error("media-control stream exited with \(ended.terminationStatus)")
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.restartLater() } }
        }
        do {
            try process.run()
        } catch {
            log.error("media-control stream failed: \(error.localizedDescription, privacy: .public)")
            restartLater()
            return
        }
        self.process = process
        let handle = output.fileHandleForReading
        // A dedicated thread holds the blocking read, which can wait for hours while nothing plays, so no shared queue stalls behind it.
        Thread.detachNewThread { [weak self] in
            var pending = Data()
            var artwork: Data?
            var tint: Tint?
            while true {
                let chunk = handle.availableData
                guard !chunk.isEmpty else { break }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = pending.prefix(upTo: newline)
                    pending.removeSubrange(...newline)
                    guard let event = try? JSONDecoder().decode(StreamEvent.self, from: line) else { continue }
                    let state = Self.state(from: event.payload)
                    if state.artwork != artwork {
                        artwork = state.artwork
                        tint = artwork.flatMap(Self.averageColor)
                    }
                    DispatchQueue.main.async { [tint] in MainActor.assumeIsolated { self?.publish(state, tint: tint) } }
                }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.publish(.idle, tint: nil) } }
        }
    }

    func stop() {
        running = false
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    func togglePlayback() {
        guard case .media = state else { return }
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = Self.mediaControl
            process.arguments = ["toggle-play-pause"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                log.error("media-control toggle failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func restartLater() {
        process = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running, self.process == nil else { return }
                self.start()
            }
        }
    }

    private func publish(_ next: NowPlayingState, tint: Tint?) {
        guard next != state else { return }
        if next.artwork != state.artwork {
            artwork = next.artwork.flatMap(NSImage.init(data:))
            self.tint = tint.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } ?? .white
        }
        state = next
        onChange()
    }

    private nonisolated static func state(from payload: StreamEvent.Payload) -> NowPlayingState {
        guard let title = payload.title, !title.isEmpty else { return .idle }
        return .media(NowPlaying(title: title, artist: payload.artist, playing: payload.playing ?? false, artwork: payload.artworkData.flatMap { Data(base64Encoded: $0) }))
    }

    // Artwork is often dark, so the average is lifted toward white until the bars read against the black island.
    private nonisolated static func averageColor(of data: Data) -> Tint? {
        guard let image = CIImage(data: data) else { return nil }
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let color = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        guard let lifted = color.blended(withFraction: max(0, 0.6 - color.brightnessComponent), of: .white)?.usingColorSpace(.sRGB) else { return nil }
        return Tint(red: lifted.redComponent, green: lifted.greenComponent, blue: lifted.blueComponent)
    }
}
