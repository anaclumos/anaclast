import Foundation
import Testing
@testable import AnaclastCore

@Suite struct ConfigFileTests {
    let config = try! Config.load(from: fixtureConfigURL)

    func scratchCopy() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "anaclast.json")
        try FileManager.default.copyItem(at: fixtureConfigURL, to: url)
        return url
    }

    @Test func configSurvivesAWriteAndRead() throws {
        let decoded = try JSONDecoder().decode(Config.self, from: config.encoded())
        #expect(decoded == config)
    }

    @Test func keystrokeActionsRoundTrip() throws {
        let action = Action.keystroke(try KeyChord(parsing: "cmd+shift+escape"))
        let decoded = try JSONDecoder().decode(Action.self, from: JSONEncoder().encode(action))
        #expect(decoded == action)
    }

    @Test func updateWritesAValidatedConfig() throws {
        let url = try scratchCopy()
        try ConfigFile.update(at: url) { $0.hyper.tapTimeoutMilliseconds = 250 }
        #expect(try Config.load(from: url).hyper.tapTimeoutMilliseconds == 250)
    }

    @Test func updateRejectsAnInvalidChangeAndKeepsTheFile() throws {
        let url = try scratchCopy()
        let before = try Data(contentsOf: url)
        #expect(throws: ConfigError.self) {
            try ConfigFile.update(at: url) { $0.hyper.keys["a"] = .tile("nowhere") }
        }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func settingAPathChangesOnlyThatValue() throws {
        let changed = try config.setting("hyper.keys.g", to: Data(#"{"tile": "left"}"#.utf8))
        #expect(changed.hyper.keys["g"] == .tile("left"))
        #expect(changed.hyper.keys.count == config.hyper.keys.count + 1)
        #expect(changed.tiles == config.tiles)
    }

    @Test func removingAPathDropsTheEntry() throws {
        let changed = try config.setting("modifierTaps.leftCommand", to: nil)
        #expect(changed.modifierTaps.leftCommand == nil)
        #expect(changed.modifierTaps.rightCommand == config.modifierTaps.rightCommand)
    }

    @Test func unknownSettingsAreRejected() {
        #expect(throws: ConfigError.self) { try config.setting("hyper.tapTimeout", to: Data("250".utf8)) }
        #expect(throws: ConfigError.self) { try config.setting("nothing.here", to: Data("1".utf8)) }
        #expect(throws: ConfigError.self) { try config.value(at: "clipboard.size") }
    }

    @Test func keystrokesInAnyModifierOrderAreAccepted() throws {
        let changed = try config.setting("hyper.keys.x", to: Data(#"{"keystroke": "cmd+shift+4"}"#.utf8))
        #expect(changed.hyper.keys["x"] == .keystroke(try KeyChord(parsing: "shift+cmd+4")))
    }

    @Test func settingNullRemovesTheEntry() throws {
        let changed = try config.setting("modifierTaps.leftCommand", to: Data("null".utf8))
        #expect(changed.modifierTaps.leftCommand == nil)
    }

    @Test func removingAMissingPathFails() {
        #expect(throws: ConfigError.self) { try config.setting("hyper.keys.zz", to: nil) }
        #expect(throws: ConfigError.self) { try config.setting("modifierTaps.leftComand", to: nil) }
    }

    @Test func unknownKeysInTheFileAreRejectedAndKept() throws {
        let url = try scratchCopy()
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["futureSetting"] = true
        let before = try JSONSerialization.data(withJSONObject: object)
        try before.write(to: url)
        #expect(throws: ConfigError.self) { try Config.load(from: url) }
        #expect(throws: ConfigError.self) { try ConfigFile.update(at: url) { $0.clipboard.limit = 100 } }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func updateRepairsAnInvalidFile() throws {
        let url = try scratchCopy()
        var broken = config
        broken.hyper.keys["x"] = .tile("nowhere")
        try ConfigFile.write(broken, to: url)
        #expect(throws: ConfigError.self) { try Config.load(from: url) }
        try ConfigFile.update(at: url) { $0.hyper.keys["x"] = nil }
        #expect(try Config.load(from: url) == config)
    }

    @Test func reservedAndAliasedNamesAreRejected() {
        var fullscreen = config
        fullscreen.tiles[Config.fullscreenTile] = TileFrame(x: 0, y: 0, w: 1, h: 1)
        #expect(throws: ConfigError.self) { try fullscreen.validate() }
        var aliased = config
        aliased.hyper.keys["esc"] = .command(.launcher)
        aliased.hyper.keys["escape"] = .command(.quit)
        #expect(throws: ConfigError.self) { try aliased.validate() }
        #expect(KeyCode(name: "esc")?.description == "escape")
        var hyperSource = config
        hyperSource.hyper.keys["f18"] = .command(.launcher)
        #expect(throws: ConfigError.self) { try hyperSource.validate() }
        #expect(!Config.hyperKeyNames.contains("f18") && !Config.hyperKeyNames.contains("capslock"))
    }

    @Test func hyperKeystrokesKeepTheirShortSpelling() throws {
        #expect(try KeyChord(parsing: "hyper+x").configText == "hyper+x")
        #expect(try KeyChord(parsing: "fn+cmd+shift+ctrl+alt+x").configText == "hyper+fn+x")
        #expect(try KeyChord(parsing: "cmd+shift+4").configText == "shift+cmd+4")
    }

    @Test func wrongTypesAreRejected() {
        #expect(throws: DecodingError.self) { try config.setting("clipboard.limit", to: Data(#""lots""#.utf8)) }
    }

    @Test func valueReadsNestedSettings() throws {
        let data = try config.setting("clipboard.limit", to: Data("500".utf8)).value(at: "clipboard.limit")
        #expect(String(decoding: data, as: UTF8.self) == "500")
    }

    @Test func clipboardLimitLeftOutKeepsAllHistory() throws {
        let unlimited = try config.setting("clipboard.limit", to: nil)
        #expect(unlimited.clipboard.limit == nil)
        try unlimited.validate()
        #expect(String(decoding: try unlimited.value(at: "clipboard.limit"), as: UTF8.self) == "null")
        let url = try scratchCopy()
        try ConfigFile.write(unlimited, to: url)
        #expect(try Config.load(from: url).clipboard.limit == nil)
        #expect(try String(contentsOf: url, encoding: .utf8).contains(#""limit" : null"#))
        #expect(try unlimited.setting("clipboard.limit", to: Data("200".utf8)).clipboard.limit == 200)
        var zero = config
        zero.clipboard.limit = 0
        #expect(throws: ConfigError.self) { try zero.validate() }
    }
}
