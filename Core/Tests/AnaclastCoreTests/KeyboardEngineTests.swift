import CoreGraphics
import Foundation
import Testing
@testable import AnaclastCore

@Suite struct KeyboardEngineTests {
    let config = try! Config.load(from: fixtureConfigURL)

    func engine() throws -> KeyboardEngine {
        KeyboardEngine(keymap: try Keymap(config: config))
    }

    func down(_ name: String, _ flags: CGEventFlags = [], at time: Double, repeating: Bool = false) -> KeyEvent {
        KeyEvent(kind: .keyDown, keyCode: KeyCode(name: name)!, flags: flags, isRepeat: repeating, time: time)
    }

    func up(_ name: String, _ flags: CGEventFlags = [], at time: Double) -> KeyEvent {
        KeyEvent(kind: .keyUp, keyCode: KeyCode(name: name)!, flags: flags, time: time)
    }

    func command(_ key: KeyCode, down: Bool, at time: Double, extra: CGEventFlags = []) -> KeyEvent {
        let device: UInt64 = key == .leftCommand ? 0x08 : 0x10
        let flags = down ? CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | device).union(extra) : extra
        return KeyEvent(kind: .flagsChanged, keyCode: key, flags: flags, time: time)
    }

    @Test func capsTapMaximizes() throws {
        var engine = try engine()
        #expect(engine.handle(down("f18", at: 0), frontmostApp: nil) == .swallow)
        #expect(engine.handle(up("f18", at: 0.1), frontmostApp: nil) == Resolution(swallow: true, actions: [.tile("maximize")]))
    }

    @Test func capsHeldTooLongDoesNothing() throws {
        var engine = try engine()
        _ = engine.handle(down("f18", at: 0), frontmostApp: nil)
        #expect(engine.handle(up("f18", at: 0.5), frontmostApp: nil) == .swallow)
    }

    @Test func hyperChordRunsActionAndSwallowsKeyUpAfterHyperRelease() throws {
        var engine = try engine()
        _ = engine.handle(down("f18", at: 0), frontmostApp: nil)
        #expect(engine.handle(down("left", at: 0.05), frontmostApp: nil) == Resolution(swallow: true, actions: [.tile("left")]))
        #expect(engine.handle(down("left", at: 0.3, repeating: true), frontmostApp: nil) == .swallow)
        #expect(engine.handle(up("f18", at: 0.35), frontmostApp: nil) == .swallow)
        #expect(engine.handle(up("left", at: 0.4), frontmostApp: nil) == .swallow)
        #expect(engine.handle(down("left", at: 1), frontmostApp: nil) == .pass)
    }

    @Test func hyperWithUnboundKeyPassesAndCancelsTap() throws {
        var engine = try engine()
        _ = engine.handle(down("f18", at: 0), frontmostApp: nil)
        #expect(engine.handle(down("x", at: 0.02), frontmostApp: nil) == .pass)
        #expect(engine.handle(up("x", at: 0.05), frontmostApp: nil) == .pass)
        #expect(engine.handle(up("f18", at: 0.1), frontmostApp: nil) == .swallow)
    }

    @Test func hyperKeysIgnoreExtraModifiers() throws {
        var engine = try engine()
        _ = engine.handle(down("f18", at: 0), frontmostApp: nil)
        #expect(engine.handle(down("h", .maskShift, at: 0.05), frontmostApp: nil) == Resolution(swallow: true, actions: [.open(bundleID: "com.apple.mail")]))
    }

    @Test func leftCommandTapRunsItsAction() throws {
        var engine = try engine()
        #expect(engine.handle(command(.leftCommand, down: true, at: 0), frontmostApp: nil) == .pass)
        #expect(engine.handle(command(.leftCommand, down: false, at: 0.2), frontmostApp: nil) == Resolution(swallow: false, actions: [.inputSource("com.apple.keylayout.US")]))
    }

    @Test func rightCommandTapRunsItsAction() throws {
        var engine = try engine()
        _ = engine.handle(command(.rightCommand, down: true, at: 0), frontmostApp: nil)
        #expect(engine.handle(command(.rightCommand, down: false, at: 0.1), frontmostApp: nil).actions == [.inputSource("com.apple.keylayout.ABC")])
    }

    @Test func commandChordIsNotATap() throws {
        var engine = try engine()
        _ = engine.handle(command(.leftCommand, down: true, at: 0), frontmostApp: nil)
        #expect(engine.handle(down("c", .maskCommand, at: 0.05), frontmostApp: nil) == .pass)
        #expect(engine.handle(command(.leftCommand, down: false, at: 0.1), frontmostApp: nil) == .pass)
    }

    @Test func commandClickIsNotATap() throws {
        var engine = try engine()
        _ = engine.handle(command(.leftCommand, down: true, at: 0), frontmostApp: nil)
        _ = engine.handle(KeyEvent(kind: .pointer, keyCode: KeyCode(0), flags: .maskCommand, time: 0.05), frontmostApp: nil)
        #expect(engine.handle(command(.leftCommand, down: false, at: 0.1), frontmostApp: nil) == .pass)
    }

    @Test func slowCommandTapIsIgnored() throws {
        var engine = try engine()
        _ = engine.handle(command(.leftCommand, down: true, at: 0), frontmostApp: nil)
        #expect(engine.handle(command(.leftCommand, down: false, at: 0.6), frontmostApp: nil) == .pass)
    }

    @Test func commandTapWithShiftAlreadyHeldStillSwitchesLikeKarabinerOptionalAny() throws {
        var engine = try engine()
        _ = engine.handle(command(.leftCommand, down: true, at: 0, extra: .maskShift), frontmostApp: nil)
        #expect(engine.handle(command(.leftCommand, down: false, at: 0.1, extra: .maskShift), frontmostApp: nil).actions == [.inputSource("com.apple.keylayout.US")])
    }

    @Test func shiftPressedDuringCommandHoldCancelsTap() throws {
        var engine = try engine()
        _ = engine.handle(command(.leftCommand, down: true, at: 0), frontmostApp: nil)
        _ = engine.handle(KeyEvent(kind: .flagsChanged, keyCode: KeyCode(56), flags: [.maskCommand, .maskShift], time: 0.05), frontmostApp: nil)
        #expect(engine.handle(command(.leftCommand, down: false, at: 0.1, extra: .maskShift), frontmostApp: nil) == .pass)
    }

    @Test func commandLLocksAndOnlyExactChord() throws {
        var engine = try engine()
        #expect(engine.handle(down("l", .maskCommand, at: 0), frontmostApp: "com.google.Chrome") == Resolution(swallow: true, actions: [.command(.lockScreen)]))
        #expect(engine.handle(up("l", .maskCommand, at: 0.05), frontmostApp: nil) == .swallow)
        #expect(engine.handle(down("l", [.maskCommand, .maskShift], at: 1), frontmostApp: nil) == .pass)
    }

    @Test func mailShortcutsOnlyInMail() throws {
        var engine = try engine()
        #expect(engine.handle(down("e", .maskCommand, at: 0), frontmostApp: "com.apple.mail") == Resolution(swallow: true, actions: [.menu(["Message", "Archive"])]))
        _ = engine.handle(up("e", .maskCommand, at: 0.05), frontmostApp: "com.apple.mail")
        #expect(engine.handle(down("e", .maskCommand, at: 1), frontmostApp: "com.apple.Safari") == .pass)
    }

    @Test func clipboardHistoryChord() throws {
        var engine = try engine()
        #expect(engine.handle(down("v", [.maskCommand, .maskShift], at: 0), frontmostApp: nil).actions == [.command(.clipboardHistory)])
    }

    @Test func hyperSpaceOpensLauncher() throws {
        var engine = try engine()
        _ = engine.handle(down("f18", at: 0), frontmostApp: nil)
        #expect(engine.handle(down("space", at: 0.05), frontmostApp: nil).actions == [.command(.launcher)])
    }

    @Test func commandSpaceOpensLauncher() throws {
        var engine = try engine()
        #expect(engine.handle(down("space", .maskCommand, at: 0), frontmostApp: nil) == Resolution(swallow: true, actions: [.command(.launcher)]))
        #expect(engine.handle(up("space", .maskCommand, at: 0.05), frontmostApp: nil) == .swallow)
    }

    func function(down: Bool, at time: Double) -> KeyEvent {
        KeyEvent(kind: .flagsChanged, keyCode: KeyCode(63), flags: down ? .maskSecondaryFn : [], time: time)
    }

    func rewritten(_ name: String, _ flags: CGEventFlags) -> Resolution {
        Resolution(swallow: false, actions: [], rewrite: Rewrite(keyCode: KeyCode(name: name)!, flags: flags))
    }

    @Test func bareSpotlightKeyBecomesF4() throws {
        var engine = try engine()
        #expect(engine.handle(down("spotlight", .maskSecondaryFn, at: 0), frontmostApp: nil) == rewritten("f4", .maskSecondaryFn))
        #expect(engine.handle(up("spotlight", .maskSecondaryFn, at: 0.05), frontmostApp: nil) == rewritten("f4", .maskSecondaryFn))
    }

    @Test func physicalFnWithF4BecomesSpotlight() throws {
        var engine = try engine()
        _ = engine.handle(function(down: true, at: 0), frontmostApp: nil)
        #expect(engine.handle(down("f4", .maskSecondaryFn, at: 0.05), frontmostApp: nil) == rewritten("spotlight", .maskSecondaryFn))
        _ = engine.handle(function(down: false, at: 0.08), frontmostApp: nil)
        #expect(engine.handle(up("f4", [], at: 0.1), frontmostApp: nil) == rewritten("spotlight", .maskSecondaryFn))
    }

    @Test func f4WithoutPhysicalFnPasses() throws {
        var engine = try engine()
        #expect(engine.handle(down("f4", .maskSecondaryFn, at: 0), frontmostApp: nil) == .pass)
        #expect(engine.handle(up("f4", .maskSecondaryFn, at: 0.05), frontmostApp: nil) == .pass)
    }

    @Test func bareSpotlightKeyKeepsShift() throws {
        var engine = try engine()
        #expect(engine.handle(down("spotlight", [.maskSecondaryFn, .maskShift], at: 0), frontmostApp: nil) == rewritten("f4", [.maskSecondaryFn, .maskShift]))
    }

    @Test func missedReleaseDoesNotEatTheNextPress() throws {
        var engine = try engine()
        #expect(engine.handle(down("l", .maskCommand, at: 0), frontmostApp: nil).actions == [.command(.lockScreen)])
        #expect(engine.handle(down("l", at: 30), frontmostApp: nil) == .pass)
        #expect(engine.handle(up("l", at: 30.05), frontmostApp: nil) == .pass)
    }

    @Test func hyperIsDroppedWhenItsKeyIsNoLongerHeld() throws {
        var engine = try engine()
        _ = engine.handle(down("f18", at: 0), frontmostApp: nil)
        let typed = KeyEvent(kind: .keyDown, keyCode: KeyCode(name: "h")!, flags: [], time: 20, hyperSourceHeld: false)
        #expect(engine.handle(typed, frontmostApp: nil) == .pass)
        #expect(engine.handle(down("h", at: 21), frontmostApp: nil) == .pass)
    }

    @Test func keyHeldBeforeHyperKeepsItsRelease() throws {
        var engine = try engine()
        #expect(engine.handle(down("h", at: 0), frontmostApp: nil) == .pass)
        _ = engine.handle(down("f18", at: 0.1), frontmostApp: nil)
        #expect(engine.handle(down("h", at: 0.5, repeating: true), frontmostApp: nil) == .pass)
        #expect(engine.handle(up("h", at: 0.6), frontmostApp: nil) == .pass)
    }

    @Test func resetDropsHeldHyper() throws {
        var engine = try engine()
        _ = engine.handle(down("f18", at: 0), frontmostApp: nil)
        engine.reset()
        #expect(engine.handle(down("h", at: 0.05), frontmostApp: nil) == .pass)
    }

    @Test func remapRepeatsKeepTheTargetChosenAtKeyDown() throws {
        var engine = try engine()
        _ = engine.handle(function(down: true, at: 0), frontmostApp: nil)
        _ = engine.handle(down("f4", .maskSecondaryFn, at: 0.05), frontmostApp: nil)
        _ = engine.handle(function(down: false, at: 0.1), frontmostApp: nil)
        #expect(engine.handle(down("f4", .maskSecondaryFn, at: 0.4, repeating: true), frontmostApp: nil) == rewritten("spotlight", .maskSecondaryFn))
    }
}

@Suite struct ConfigTests {
    @Test func repoConfigLoads() throws {
        _ = try Config.load(from: repoConfigURL)
    }

    @Test func actionNeedsExactlyOneKey() {
        let json = #"{"tile": "left", "open": "com.apple.mail"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Action.self, from: Data(json.utf8)) }
    }

    @Test func unknownActionRejected() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Action.self, from: Data(#"{"tiel": "left"}"#.utf8)) }
    }

    @Test func windowActionDecodes() throws {
        let json = #"{"window": {"name": "Notes", "app": "com.example.notes", "exceptTitle": "Settings", "launch": ["Contents/MacOS/notes", "--new"]}}"#
        let action = try JSONDecoder().decode(Action.self, from: Data(json.utf8))
        #expect(action == .window(WindowTarget(name: "Notes", app: "com.example.notes", exceptTitle: "Settings", launch: ["Contents/MacOS/notes", "--new"])))
    }

    @Test func windowTargetMatchesTitles() {
        let exact = WindowTarget(name: "Inbox", app: "com.example.mail", title: "Inbox")
        #expect(exact.matches(title: "Inbox"))
        #expect(!exact.matches(title: "Drafts"))
        let other = WindowTarget(name: "Editor", app: "com.example.editor", exceptTitle: "Inbox")
        #expect(other.matches(title: "Drafts"))
        #expect(!other.matches(title: "Inbox"))
        #expect(!other.matches(title: ""))
    }

    @Test func windowActionNeedsAnAppAndAnExecutable() throws {
        var config = try Config.load(from: fixtureConfigURL)
        config.hyper.keys["x"] = .window(WindowTarget(name: "Empty", app: "com.example.app", launch: []))
        #expect(throws: ConfigError.self) { try config.validate() }
        config.hyper.keys["x"] = .window(WindowTarget(name: "Empty", app: ""))
        #expect(throws: ConfigError.self) { try config.validate() }
    }

    @Test func keystrokeParses() throws {
        let action = try JSONDecoder().decode(Action.self, from: Data(#"{"keystroke": "ctrl+m"}"#.utf8))
        #expect(action == .keystroke(KeyChord(key: KeyCode(name: "m")!, modifiers: .control)))
    }

    @Test func unknownChordModifierRejected() {
        #expect(throws: ConfigError.self) { try KeyChord(parsing: "super+l") }
    }

    @Test func remapSourceMayOnlyRequireFn() throws {
        var config = try Config.load(from: fixtureConfigURL)
        config.remaps.append(Remap(from: "cmd+f5", to: "fn+dictation"))
        #expect(throws: ConfigError.invalid(#"remap "cmd+f5" may only require fn"#)) { try config.validate() }
    }
}

@Suite struct TilingTests {
    @Test func leftHalf() {
        let frame = Tiling.frame(for: TileFrame(x: 0, y: 0, w: 0.5, h: 1), in: CGRect(x: 0, y: 33, width: 1728, height: 1084))
        #expect(frame == CGRect(x: 0, y: 33, width: 864, height: 1084))
    }

    @Test func screenWithLargestOverlapWins() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        #expect(Tiling.screenIndex(for: CGRect(x: 900, y: 100, width: 400, height: 300), among: screens) == 1)
    }

    @Test func flipConvertsBottomLeftToTopLeft() {
        #expect(Tiling.flipped(CGRect(x: 0, y: 0, width: 100, height: 50), primaryHeight: 1117) == CGRect(x: 0, y: 1067, width: 100, height: 50))
    }
}

@Suite struct SearchTests {
    @Test func prefixBeatsScattered() {
        let hits = Searcher().rank(["Slack", "Sublime Text", "System Settings"], query: "sla", title: { $0 })
        #expect(hits.first?.item == "Slack")
    }

    @Test func prefixBeatsLooseMatchesInLongerNames() {
        let hits = Searcher().rank(["StarCraft II Editor", "StarCraft Launcher", "Safari"], query: "saf", title: { $0 })
        #expect(hits.first?.item == "Safari")
    }

    @Test func wordStartBeatsMidWord() {
        let hits = Searcher().rank(["balenaEtcher", "Time Machine", "SC2Switcher", "Google Chrome"], query: "ch", title: { $0 })
        #expect(hits.first?.item == "Google Chrome")
    }

    @Test func titlePrefixBreaksTies() {
        let hits = Searcher().rank(["Sublime Text", "TextEdit"], query: "te", title: { $0 })
        #expect(hits.map(\.item) == ["TextEdit", "Sublime Text"])
    }

    @Test func typosStillFindTheApp() {
        let apps = ["Google Chrome", "Slack", "Safari", "Calendar", "Messages"]
        #expect(Searcher().rank(apps, query: "slakc", title: { $0 }).first?.item == "Slack")
        #expect(Searcher().rank(apps, query: "crhome", title: { $0 }).first?.item == "Google Chrome")
    }

    @Test func hangulQueriesNeedTheWordAsWritten() {
        let hits = Searcher().rank(["각검", "사가"], query: "가", title: { $0 })
        #expect(hits.map(\.item) == ["사가"])
    }

    @Test func keywordsMatch() {
        let hits = Searcher().rank(["Tile Left"], query: "left half", title: { $0 }, keywords: { _ in ["left half"] })
        #expect(hits.count == 1)
    }

    @Test func emptyQueryOrdersByUse() {
        let uses = ["Mail": 1, "Zoom": 9]
        let hits = Searcher().rank(["Mail", "Zoom"], query: "", title: { $0 }, uses: { uses[$0]! })
        #expect(hits.map(\.item) == ["Zoom", "Mail"])
    }
}

let repoConfigDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "config")
let repoConfigURL = repoConfigDirectory.appending(path: "dotfiles/anaclast/config.json")

let configFixture = #"""
{
  "clipboard" : { "limit" : 500 },
  "disabledSymbolicHotkeys" : [64],
  "hyper" : {
    "keys" : {
      "h" : { "open" : "com.apple.mail" },
      "left" : { "tile" : "left" },
      "space" : { "command" : "launcher" }
    },
    "tap" : { "tile" : "maximize" },
    "tapTimeoutMilliseconds" : 200
  },
  "modifierTaps" : {
    "leftCommand" : { "inputSource" : "com.apple.keylayout.US" },
    "rightCommand" : { "inputSource" : "com.apple.keylayout.ABC" },
    "timeoutMilliseconds" : 500
  },
  "remaps" : [
    { "from" : "spotlight", "to" : "fn+f4" },
    { "from" : "fn+f4", "to" : "fn+spotlight" }
  ],
  "shortcuts" : [
    { "action" : { "command" : "launcher" }, "chord" : "cmd+space" },
    { "action" : { "command" : "lockScreen" }, "chord" : "cmd+l" },
    { "action" : { "command" : "clipboardHistory" }, "chord" : "cmd+shift+v" },
    { "action" : { "menu" : ["Message", "Archive"] }, "app" : "com.apple.mail", "chord" : "cmd+e" }
  ],
  "tiles" : {
    "left" : { "h" : 1, "w" : 0.5, "x" : 0, "y" : 0 },
    "maximize" : { "h" : 1, "w" : 1, "x" : 0, "y" : 0 }
  }
}
"""#

let fixtureConfigURL: URL = {
    let url = FileManager.default.temporaryDirectory.appending(path: "anaclast-config-fixture-\(UUID().uuidString).json")
    try! Data(configFixture.utf8).write(to: url)
    return url
}()
