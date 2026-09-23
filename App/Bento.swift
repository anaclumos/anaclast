import SwiftUI

struct BentoGrid: View {
    let status: SystemStatus

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 8
            let row = (proxy.size.height - 2 * gap) / 3
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        ClockTile()
                        WeatherTile(weather: status.weather)
                    }
                    .frame(height: row)
                    HStack(spacing: gap) {
                        BatteryTile(battery: status.battery)
                        MailTile(mail: status.mail)
                    }
                    .frame(height: row)
                    NowPlayingTile(state: status.media.state, toggle: status.media.togglePlayback)
                        .frame(height: row)
                }
                VStack(spacing: gap) {
                    CalendarTile(state: status.calendar)
                        .frame(height: 2 * row + gap)
                    HStack(spacing: gap) {
                        NetworkTile(network: status.network)
                        LoadTile(cpu: status.cpu, memory: status.memory)
                    }
                    .frame(height: row)
                }
            }
        }
        .padding(12)
    }
}

// Every tile shares one skeleton, so headers, headlines and captions in a row sit on the same baselines.
private struct Tile<Content: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    var link: URL?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let link {
                Link(destination: link) { header }
            } else {
                header
            }
            content
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 18))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
        .lineLimit(1)
    }
}

private struct Headline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct Caption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct ClockTile: View {
    var body: some View {
        Tile(title: "Clock", symbol: "clock") {
            TimelineView(.everyMinute) { context in
                Headline(text: context.date.formatted(.dateTime.hour().minute()))
                Caption(text: context.date.formatted(.dateTime.weekday(.wide).month().day()))
            }
        }
    }
}

struct BatteryTile: View {
    let battery: BatteryStatus?

    var body: some View {
        Tile(title: "Battery", symbol: symbol) {
            if let battery {
                Headline(text: "\(battery.percent)%")
                Caption(text: detail(battery))
            } else {
                Caption(text: "No battery")
            }
        }
    }

    private var symbol: String {
        guard let battery else { return "powerplug" }
        if battery.charging { return "battery.100percent.bolt" }
        return switch battery.percent {
        case 88...: "battery.100percent"
        case 63..<88: "battery.75percent"
        case 38..<63: "battery.50percent"
        case 13..<38: "battery.25percent"
        default: "battery.0percent"
        }
    }

    private func detail(_ battery: BatteryStatus) -> String {
        let left = battery.minutesLeft.map { Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) }
        if battery.charging { return left.map { "Charging, full in \($0)" } ?? "Charging" }
        if battery.onPower { return "On power" }
        return left.map { "\($0) left" } ?? "On battery"
    }
}

struct CalendarTile: View {
    let state: CalendarState

    var body: some View {
        TimelineView(.everyMinute) { context in
            Tile(title: context.date.formatted(.dateTime.weekday(.wide)).uppercased(), symbol: "calendar", tint: .red) {
                Headline(text: context.date.formatted(.dateTime.day()))
                switch state {
                case .waiting:
                    EmptyView()
                case .denied:
                    Caption(text: "Calendar access is off")
                case .events(let items) where items.isEmpty:
                    Caption(text: "No more events today")
                case .events(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items.prefix(3)) { item in
                            EventRow(item: item)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

private struct EventRow: View {
    let item: CalendarItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Capsule()
                .fill(item.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(item.allDay ? "All day" : "\(item.start.formatted(date: .omitted, time: .shortened)) to \(item.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct WeatherTile: View {
    let weather: WeatherState

    private static let degrees = Measurement<UnitTemperature>.FormatStyle(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))

    var body: some View {
        switch weather {
        case .waiting:
            Tile(title: "Weather", symbol: "cloud.sun") { EmptyView() }
        case .noLocation:
            Tile(title: "Weather", symbol: "cloud.sun") { Caption(text: "Location access is off") }
        case .unavailable:
            Tile(title: "Weather", symbol: "cloud.sun") { Caption(text: "Weather unavailable") }
        case .ready(let now):
            Tile(title: "Weather", symbol: "apple.logo", link: now.legal) {
                Headline(text: now.temperature.formatted(Self.degrees))
                Caption(text: now.condition)
                Caption(text: "H \(now.high.formatted(Self.degrees))  L \(now.low.formatted(Self.degrees))")
            }
        }
    }
}

struct NowPlayingTile: View {
    let state: NowPlayingState
    let toggle: () -> Void

    var body: some View {
        Tile(title: "Now Playing", symbol: "music.note") {
            switch state {
            case .missing:
                Caption(text: "media-control isn't installed")
            case .idle:
                Caption(text: "Nothing playing")
            case .media(let media):
                HStack(spacing: 12) {
                    Artwork(data: media.artwork)
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                        if let artist = media.artist {
                            Text(artist)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Button(action: toggle) {
                        Image(systemName: media.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct Artwork: View {
    let data: Data?

    var body: some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(.white.opacity(0.08))
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
    }
}

struct MailTile: View {
    let mail: MailState

    var body: some View {
        Tile(title: "Mail", symbol: "envelope") {
            switch mail {
            case .closed:
                Caption(text: "Mail isn't open")
            case .unavailable:
                Caption(text: "No access to Mail")
            case .unread(0):
                Headline(text: "0")
                Caption(text: "No unread mail")
            case .unread(let count):
                Headline(text: count.formatted())
                Caption(text: "Unread in Inbox")
            }
        }
    }
}

struct NetworkTile: View {
    let network: NetworkStatus?

    var body: some View {
        Tile(title: "Network", symbol: network.map { symbol($0.kind) } ?? "network") {
            if let network {
                Headline(text: title(network))
                Caption(text: detail(network))
            }
        }
    }

    private func symbol(_ kind: NetworkStatus.Kind) -> String {
        switch kind {
        case .wifi: "wifi"
        case .ethernet: "cable.connector"
        case .other: "network"
        case .offline: "wifi.slash"
        }
    }

    private func title(_ network: NetworkStatus) -> String {
        switch network.kind {
        case .wifi: network.name ?? "Wi-Fi"
        case .ethernet: "Ethernet"
        case .other: "Connected"
        case .offline: "Offline"
        }
    }

    private func detail(_ network: NetworkStatus) -> String {
        guard network.kind == .wifi, let rssi = network.rssi else { return network.kind == .offline ? "No connection" : "Online" }
        return "\(rssi) dBm"
    }
}

struct LoadTile: View {
    let cpu: Double?
    let memory: MemoryStatus?

    private static let count: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.includesUnit = false
        return formatter
    }()

    var body: some View {
        Tile(title: "System", symbol: "cpu") {
            VStack(alignment: .leading, spacing: 8) {
                Meter(label: "CPU", value: cpu.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "", fraction: cpu ?? 0)
                Meter(
                    label: "Memory",
                    value: memory.map { "\(Self.count.string(fromByteCount: Int64($0.used)))/\($0.total.formatted(.byteCount(style: .memory)))" } ?? "",
                    fraction: memory.map { Double($0.used) / Double($0.total) } ?? 0
                )
            }
            .padding(.top, 4)
        }
    }
}

private struct Meter: View {
    let label: String
    let value: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                Text(value).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            Capsule()
                .fill(.white.opacity(0.12))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(.white.opacity(0.7)).frame(width: proxy.size.width * min(1, max(0, fraction)))
                    }
                }
        }
    }
}
