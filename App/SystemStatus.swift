import AppKit
import CoreLocation
import CoreWLAN
import EventKit
import IOKit.ps
import Network
import Observation
import ScriptingBridge
import SwiftUI
import WeatherKit

struct BatteryStatus: Equatable {
    let percent: Int
    let charging: Bool
    let onPower: Bool
    let minutesLeft: Int?
}

struct MemoryStatus: Equatable {
    let used: UInt64
    let total: UInt64
}

struct CalendarItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
}

struct NetworkStatus: Equatable {
    enum Kind { case wifi, ethernet, other, offline }
    let kind: Kind
    let name: String?
    let rssi: Int?
}

enum CalendarState: Equatable {
    case waiting
    case denied
    case events([CalendarItem])
}

enum MailState: Equatable {
    case closed
    case unavailable
    case unread(Int)
}

struct WeatherStatus: Equatable {
    let temperature: Measurement<UnitTemperature>
    let high: Measurement<UnitTemperature>
    let low: Measurement<UnitTemperature>
    let symbol: String
    let condition: String
    let mark: URL
    let legal: URL
}

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
}

private struct MediaPayload: Decodable {
    let title: String?
    let artist: String?
    let playing: Bool?
    let artworkData: String?
}

enum WeatherState: Equatable {
    case waiting
    case noLocation
    case unavailable
    case ready(WeatherStatus)
}

// events(matching:) is synchronous, so the store lives off the main thread where the launcher springs open.
private actor CalendarReader {
    private let store = EKEventStore()

    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
    }

    func today() -> [CalendarItem] {
        let start = Date.now
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
            .map { CalendarItem(id: $0.calendarItemIdentifier + $0.startDate.formatted(.iso8601), title: $0.title ?? "", start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay, color: Color(nsColor: $0.calendar.color)) }
    }
}

@MainActor
@Observable
final class SystemStatus: NSObject {
    private(set) var battery: BatteryStatus?
    private(set) var cpu: Double?
    private(set) var memory: MemoryStatus?
    private(set) var calendar = CalendarState.waiting
    private(set) var network: NetworkStatus?
    private(set) var mail = MailState.closed
    private(set) var weather = WeatherState.waiting
    private(set) var nowPlaying = NowPlayingState.idle
    @ObservationIgnored private let mediaQueue = DispatchQueue(label: "com.anaclumos.anaclast.media")
    @ObservationIgnored private var weatherTask: Task<Void, Never>?
    @ObservationIgnored private var weatherFetched: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks: [UInt32]?
    @ObservationIgnored private let reader = CalendarReader()
    @ObservationIgnored private let path = NWPathMonitor()
    @ObservationIgnored private let location = CLLocationManager()
    @ObservationIgnored private let mailQueue = DispatchQueue(label: "com.anaclumos.anaclast.mail")

    override init() {
        super.init()
        location.delegate = self
        path.pathUpdateHandler = { [weak self] _ in
            MainActor.assumeIsolated { self?.readNetwork() }
        }
        path.start(queue: .main)
    }

    func start() {
        stop()
        sample()
        refreshCalendar()
        refreshMail()
        refreshWeather()
        refreshNowPlaying()
        if EKEventStore.authorizationStatus(for: .event) != .notDetermined { requestLocation() }
        let timer = Timer(fire: .now + 0.5, interval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        ticks = nil
    }

    private func sample() {
        battery = Self.readBattery()
        memory = Self.readMemory()
        readNetwork()
        guard let now = Self.readTicks() else { return }
        if let previous = ticks {
            let delta = zip(now, previous).map { Double($0 &- $1) }
            let total = delta.reduce(0, +)
            if total > 0 { cpu = (delta[Int(CPU_STATE_USER)] + delta[Int(CPU_STATE_SYSTEM)] + delta[Int(CPU_STATE_NICE)]) / total }
        }
        ticks = now
    }

    private func refreshCalendar() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            Task { [weak self, reader] in
                let items = await reader.today()
                self?.calendar = .events(items)
            }
        case .notDetermined:
            Task { [weak self, reader] in
                await reader.requestAccess()
                self?.refreshCalendar()
            }
        default:
            calendar = .denied
        }
    }

    private func requestLocation() {
        guard location.authorizationStatus == .notDetermined else { return }
        NSApp.activate()
        location.requestWhenInUseAuthorization()
    }

    private func refreshWeather() {
        guard location.authorizationStatus == .authorizedAlways else {
            if location.authorizationStatus != .notDetermined { weather = .noLocation }
            return
        }
        if let weatherFetched, Date.now.timeIntervalSince(weatherFetched) < 15 * 60 { return }
        guard weatherTask == nil else { return }
        weatherTask = Task { [weak self] in
            let state = await Self.fetchWeather()
            self?.weather = state
            if case .ready = state { self?.weatherFetched = .now }
            self?.weatherTask = nil
        }
    }

    private static func fetchWeather() async -> WeatherState {
        do {
            var here: CLLocation?
            for try await update in CLLocationUpdate.liveUpdates() {
                if let found = update.location {
                    here = found
                    break
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted { return .noLocation }
                if update.stationary || update.insufficientlyInUse || update.locationUnavailable || update.accuracyLimited || update.serviceSessionRequired {
                    log.error("weather has no location fix")
                    return .unavailable
                }
            }
            guard let here else { return .unavailable }
            let service = WeatherService.shared
            let (current, daily) = try await service.weather(for: here, including: .current, .daily)
            let attribution = try await service.attribution
            guard let today = daily.first else { return .unavailable }
            return .ready(WeatherStatus(
                temperature: current.temperature,
                high: today.highTemperature,
                low: today.lowTemperature,
                symbol: current.symbolName,
                condition: current.condition.description,
                mark: attribution.combinedMarkDarkURL,
                legal: attribution.legalPageURL
            ))
        } catch {
            log.error("weather unavailable: \(error.localizedDescription, privacy: .public)")
            return .unavailable
        }
    }

    nonisolated static let mediaControl = URL(filePath: "/opt/homebrew/bin/media-control")

    func togglePlayback() {
        mediaQueue.async { [weak self] in
            guard Self.runMediaControl("toggle-play-pause") != nil else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, case .media(var media) = self.nowPlaying else { return }
                    media.playing.toggle()
                    self.nowPlaying = .media(media)
                }
            }
        }
    }

    private func refreshNowPlaying() {
        guard FileManager.default.isExecutableFile(atPath: Self.mediaControl.path) else {
            nowPlaying = .missing
            return
        }
        mediaQueue.async { [weak self] in
            let payload = Self.runMediaControl("get").flatMap { try? JSONDecoder().decode(MediaPayload?.self, from: $0) } ?? nil
            let state: NowPlayingState = if let payload, let title = payload.title, !title.isEmpty {
                .media(NowPlaying(title: title, artist: payload.artist, playing: payload.playing ?? false, artwork: payload.artworkData.flatMap { Data(base64Encoded: $0) }))
            } else {
                .idle
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.nowPlaying = state } }
        }
    }

    private nonisolated static func runMediaControl(_ command: String) -> Data? {
        let process = Process()
        process.executableURL = mediaControl
        process.arguments = [command]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("media-control \(command, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if process.isRunning { process.terminate() } }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private func refreshMail() {
        mailQueue.async { [weak self] in
            let state: MailState
            if let app = SBApplication(bundleIdentifier: "com.apple.mail"), app.isRunning {
                app.timeout = 5 * 60
                let inbox = app.value(forKey: "inbox") as? SBObject
                state = (inbox?.value(forKey: "unreadCount") as? NSNumber).map { .unread($0.intValue) } ?? .unavailable
            } else {
                state = .closed
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.mail = state }
            }
        }
    }

    private func readNetwork() {
        let current = path.currentPath
        guard current.status == .satisfied else {
            network = NetworkStatus(kind: .offline, name: nil, rssi: nil)
            return
        }
        if current.usesInterfaceType(.wifi), let wifi = CWWiFiClient.shared().interface() {
            network = NetworkStatus(kind: .wifi, name: wifi.ssid(), rssi: wifi.rssiValue())
        } else {
            network = NetworkStatus(kind: current.usesInterfaceType(.wiredEthernet) ? .ethernet : .other, name: nil, rssi: nil)
        }
    }

    private static func readBattery() -> BatteryStatus? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let minutes = description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            return BatteryStatus(
                percent: current * 100 / max,
                charging: charging,
                onPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesLeft: minutes.flatMap { $0 > 0 ? $0 : nil }
            )
        }
        return nil
    }

    private static func readTicks() -> [UInt32]? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        return [load.cpu_ticks.0, load.cpu_ticks.1, load.cpu_ticks.2, load.cpu_ticks.3]
    }

    private static func readMemory() -> MemoryStatus? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        var page: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(mach_host_self(), &page) == KERN_SUCCESS else { return nil }
        let pages = UInt64(max(Int64(stats.internal_page_count) - Int64(stats.purgeable_count), 0)) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return MemoryStatus(used: pages * UInt64(page), total: ProcessInfo.processInfo.physicalMemory)
    }
}

extension SystemStatus: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard timer != nil else { return }
            refreshWeather()
        }
    }
}
