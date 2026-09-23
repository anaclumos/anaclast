import CoreGraphics

public enum Tiling {
    public static func frame(for tile: TileFrame, in area: CGRect) -> CGRect {
        CGRect(
            x: area.minX + area.width * tile.x,
            y: area.minY + area.height * tile.y,
            width: area.width * tile.w,
            height: area.height * tile.h
        )
    }

    public static func screenIndex(for window: CGRect, among screens: [CGRect]) -> Int? {
        let overlaps = screens.map { screen -> CGFloat in
            let overlap = screen.intersection(window)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }) else { return nil }
        if overlaps[best] > 0 { return best }
        let center = CGPoint(x: window.midX, y: window.midY)
        return screens.firstIndex { $0.contains(center) } ?? best
    }

    public static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
