import Foundation

extension Config {
    public static let starter: Config = try! JSONDecoder().decode(Config.self, from: Data(#"""
    {
      "clipboard": { "limit": 500 },
      "disabledSymbolicHotkeys": [],
      "hyper": {
        "keys": {
          "c": { "tile": "center" },
          "comma": { "command": "openSettings" },
          "down": { "tile": "bottom" },
          "left": { "tile": "left" },
          "return": { "tile": "fullscreen" },
          "right": { "tile": "right" },
          "space": { "command": "launcher" },
          "tab": { "command": "toggleCapsLock" },
          "up": { "tile": "top" },
          "v": { "command": "clipboardHistory" }
        },
        "tap": { "tile": "maximize" },
        "tapTimeoutMilliseconds": 200
      },
      "modifierTaps": { "timeoutMilliseconds": 500 },
      "remaps": [],
      "shortcuts": [],
      "tiles": {
        "bottom": { "h": 0.5, "w": 1, "x": 0, "y": 0.5 },
        "center": { "h": 0.75, "w": 0.75, "x": 0.125, "y": 0.125 },
        "left": { "h": 1, "w": 0.5, "x": 0, "y": 0 },
        "maximize": { "h": 1, "w": 1, "x": 0, "y": 0 },
        "right": { "h": 1, "w": 0.5, "x": 0.5, "y": 0 },
        "top": { "h": 0.5, "w": 1, "x": 0, "y": 0 }
      }
    }
    """#.utf8))
}

extension ConfigFile {
    // Only a path with nothing at it gets the starter. A dangling link means the owner's own setup is missing, and writing through it would replace the link.
    @discardableResult
    public static func createStarter(at url: URL) throws -> Bool {
        guard (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))) == nil else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(Config.starter, to: url)
        return true
    }
}
