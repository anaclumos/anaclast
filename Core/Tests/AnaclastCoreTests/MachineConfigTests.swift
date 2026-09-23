import Foundation
import Testing
@testable import AnaclastCore

let fixtureHome = "/Users/sc"

let machineFixture = #"""
{
  "homebrew": {
    "taps": ["getsentry/tools", "inngest/tap", "parallel-web/tap"],
    "brews": [
      "agent-browser", "mas", "mole", "pi-coding-agent", "playwright-cli", "pscale", "getsentry/tools/sentry", "stripe-cli",
      { "name": "tailscale", "restartService": "changed", "startService": true },
      "vercel", "watch", "tree"
    ],
    "casks": [
      "1password", "chatgpt", "codexbar", "cursor", "cursor-cli", "ghostty", "google-chrome", "iina", "inngest/tap/inngest",
      "itsycal", "karabiner-elements", "keka", "linear", "logi-options+", "macs-fan-control", "obsidian", "ollama-app",
      "orbstack", "paper-design", "parallel-web/tap/parallel-cli", "slack", "sublime-text", "t3-code", "tablepro", "zen", "zoom"
    ],
    "mas": { "Amphetamine": 937984704, "KakaoTalk": 869223134 },
    "keep": { "brews": ["xcodegen"], "casks": ["hammerspoon"] },
    "cleanup": true
  },
  "preferences": [
    { "domain": "NSGlobalDomain", "key": "com.apple.keyboard.fnState", "value": false },
    { "domain": "NSGlobalDomain", "key": "AppleTemperatureUnit", "value": "Celsius" },
    { "domain": "NSGlobalDomain", "key": "AppleMeasurementUnits", "value": "Centimeters" },
    { "domain": "NSGlobalDomain", "key": "AppleMetricUnits", "value": 1 },
    { "domain": "NSGlobalDomain", "key": "_HIHideMenuBar", "value": false },
    { "domain": "NSGlobalDomain", "key": "AppleMenuBarVisibleInFullscreen", "value": true },
    { "domain": "com.apple.HIToolbox", "key": "AppleFnUsageType", "value": 2 },
    { "domain": "com.apple.menuextra.clock", "key": "ShowDate", "value": 2 },
    { "domain": "com.apple.finder", "key": "ShowHardDrivesOnDesktop", "value": true },
    { "domain": "com.apple.finder", "key": "ShowPathbar", "value": true },
    { "domain": "com.apple.finder", "key": "ShowStatusBar", "value": true },
    { "domain": "com.apple.dock", "key": "persistent-apps", "value": [] },
    {
      "domain": "com.apple.dock", "key": "persistent-others",
      "value": [{ "tile-data": { "file-data": { "_CFURLString": "file://${HOME}/Downloads/", "_CFURLStringType": 15 } }, "tile-type": "directory-tile" }]
    },
    { "domain": "com.apple.dock", "key": "show-recents", "value": false },
    { "domain": "com.apple.controlcenter", "key": "AutoHideMenuBarOption", "value": 3 },
    { "domain": "com.apple.TextInputMenu", "key": "visible", "value": false },
    { "domain": "com.apple.TextInputMenuAgent", "key": "NSStatusItem VisibleCC Item-0", "value": false },
    { "domain": "com.apple.systemuiserver", "key": "NSStatusItem VisibleCC com.apple.menuextra.TimeMachine", "value": false },
    { "domain": "com.apple.systemuiserver", "key": "NSStatusItem Visible com.apple.menuextra.TimeMachine", "value": false },
    { "domain": "com.apple.systemuiserver", "key": "menuExtras", "value": [] },
    {
      "domain": "com.apple.finder", "key": "DesktopViewSettings",
      "value": {
        "IconViewSettings": {
          "arrangeBy": "grid", "backgroundColorBlue": 1.0, "backgroundColorGreen": 1.0, "backgroundColorRed": 1.0, "backgroundType": 0,
          "gridOffsetX": 0.0, "gridOffsetY": 0.0, "gridSpacing": 54.0, "iconSize": 64.0, "labelOnBottom": false,
          "showIconPreview": true, "showItemInfo": true, "textSize": 12.0, "viewOptionsVersion": 1
        }
      }
    },
    { "domain": "com.apple.Siri", "key": "StatusMenuVisible", "currentHost": true, "value": false }
  ],
  "restart": { "com.apple.dock": "Dock", "com.apple.finder": "Finder", "com.apple.systemuiserver": "SystemUIServer" },
  "links": [
    { "source": "dotfiles/zsh/lib", "target": "~/.config/zsh/lib" },
    { "source": "dotfiles/zsh/rc", "target": "~/.config/zsh/rc" },
    { "source": "dotfiles/ssh/config", "target": "~/.ssh/config" },
    { "source": "dotfiles/cursor/User/keybindings.json", "target": "${HOME}/Library/Application Support/Cursor/User/keybindings.json" }
  ],
  "clones": [{ "url": "https://github.com/ohmyzsh/ohmyzsh.git", "path": "~/.oh-my-zsh" }],
  "downloads": [
    {
      "name": "resend-cli", "url": "https://github.com/resend/resend-cli/releases/latest/download/resend-darwin-arm64.tar.gz", "format": "tar.gz",
      "install": [{ "from": "resend", "to": "~/.local/bin/resend", "executable": true }]
    }
  ],
  "bunGlobals": ["@linqapp/cli", "agent-slack", "linearis", "mcporter", "mint", "ntn", "starcovery", "tokenmaxxing"],
  "sudoLocal": "auth       optional       /opt/homebrew/lib/pam/pam_reattach.so\nauth       sufficient     pam_tid.so\n",
  "remoteLogin": true,
  "hosts": {
    "auracomputer": {
      "computerName": "Auracomputer", "hostName": "auracomputer", "localHostName": "auracomputer",
      "authorizedKeys": ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIfIuLXlMZdhVBuskXewHup9R9abgg/ToF2ffewtFeNT"]
    },
    "twelvecomputer": {
      "computerName": "Twelvecomputer", "hostName": "twelvecomputer", "localHostName": "twelvecomputer",
      "env": { "SUNGHYUN_CURSOR_USAGE_PUSH": "0", "SUNGHYUN_WORKSPACE": "${HOME}/Developer/TwelveLabs" },
      "authorizedKeys": ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZleyz9sVAw+hKMfzePlCR2eKl+YVLmNceuHt6XsVey"],
      "casks": ["okta-verify", "openvpn-connect", "zoom"]
    },
    "default": {}
  }
}
"""#

func loadFixture(_ json: String = machineFixture) throws -> MachineConfig {
    try MachineConfig.decode(Data(json.utf8), home: fixtureHome)
}

func fixtureReplacing(_ original: String, with replacement: String) -> String {
    #expect(machineFixture.contains(original), "fixture edit target \(original) is missing")
    return machineFixture.replacing(original, with: replacement)
}

func loadError(_ json: String) -> String? {
    do {
        _ = try loadFixture(json)
        return nil
    } catch {
        return String(describing: error)
    }
}

@Suite struct MachineConfigTests {
    @Test func loadsEverySection() throws {
        let config = try loadFixture()
        #expect(config.homebrew.taps.count == 3)
        #expect(config.homebrew.brews.count == 12)
        #expect(config.homebrew.casks.count == 26)
        #expect(config.homebrew.mas == ["Amphetamine": 937984704, "KakaoTalk": 869223134])
        #expect(config.preferences.count == 22)
        #expect(config.restart.count == 3)
        #expect(config.links.count == 4)
        #expect(config.clones.count == 1)
        #expect(config.downloads.first?.install.first?.executable == true)
        #expect(config.bunGlobals.count == 8)
        #expect(config.remoteLogin)
        #expect(Set(config.hosts.keys) == ["auracomputer", "twelvecomputer", "default"])
        let tailscale = try #require(config.homebrew.brews.first { $0.name == "tailscale" })
        #expect(tailscale.startService)
        #expect(tailscale.restartService == .changed)
        #expect(config.homebrew.brews.filter(\.startService).map(\.name) == ["tailscale"])
    }

    @Test func preferenceValuesKeepPlistTypes() throws {
        let config = try loadFixture()
        let desktop = try #require(config.preferences.first { $0.key == "DesktopViewSettings" }?.value as? [String: Any])
        let icons = try #require(desktop["IconViewSettings"] as? [String: Any])
        #expect(String(cString: try #require(icons["gridSpacing"] as? NSNumber).objCType) == "d")
        #expect(String(cString: try #require(icons["viewOptionsVersion"] as? NSNumber).objCType) == "q")
        let labelOnBottom = try #require(icons["labelOnBottom"] as? NSNumber)
        #expect(CFGetTypeID(labelOnBottom) == CFBooleanGetTypeID())
        let metric = try #require(config.preferences.first { $0.key == "AppleMetricUnits" }?.value as? NSNumber)
        #expect(CFGetTypeID(metric) != CFBooleanGetTypeID())
        let siri = try #require(config.preferences.first { $0.domain == "com.apple.Siri" })
        #expect(siri.currentHost)
        #expect(config.preferences.filter(\.currentHost).count == 1)
    }

    @Test func expandsHomeInEveryStringAndTildeInPaths() throws {
        let config = try loadFixture()
        let others = try #require(config.preferences.first { $0.key == "persistent-others" }?.value as? [[String: Any]])
        let fileData = try #require((others.first?["tile-data"] as? [String: Any])?["file-data"] as? [String: Any])
        #expect(fileData["_CFURLString"] as? String == "file:///Users/sc/Downloads/")
        #expect(config.links.map(\.target) == [
            "/Users/sc/.config/zsh/lib",
            "/Users/sc/.config/zsh/rc",
            "/Users/sc/.ssh/config",
            "/Users/sc/Library/Application Support/Cursor/User/keybindings.json",
        ])
        #expect(config.links.first?.source == "dotfiles/zsh/lib")
        #expect(config.clones.first?.path == "/Users/sc/.oh-my-zsh")
        #expect(config.downloads.first?.install.first?.to == "/Users/sc/.local/bin/resend")
        #expect(config.hosts["twelvecomputer"]?.env?["SUNGHYUN_WORKSPACE"] == "/Users/sc/Developer/TwelveLabs")
    }

    @Test func rejectsUnknownKeysNamingThePath() {
        let cases = [
            (#""remoteLogin": true,"#, #""remoteLogin": true, "remoteLgoin": false,"#, "unknown key \"remoteLgoin\" in the top level"),
            (#""restartService": "changed""#, #""restartServce": "changed""#, "unknown key \"restartServce\" in homebrew.brews[8]"),
            (#""cleanup": true"#, #""cleanup": true, "upgrade": true"#, "unknown key \"upgrade\" in homebrew"),
            (#""key": "ShowDate","#, #""key": "ShowDate", "host": true,"#, "unknown key \"host\" in preferences[7]"),
            (#""executable": true"#, #""executable": true, "mode": 493"#, "unknown key \"mode\" in downloads[0].install[0]"),
            (#""casks": ["okta-verify""#, #""cask": [], "casks": ["okta-verify""#, "unknown key \"cask\" in hosts.twelvecomputer"),
            (#""keep": { "brews": ["xcodegen"]"#, #""keep": { "formulae": [], "brews": ["xcodegen"]"#, "unknown key \"formulae\" in homebrew.keep"),
        ]
        for (original, replacement, message) in cases {
            #expect(loadError(fixtureReplacing(original, with: replacement)) == message)
        }
    }

    @Test func leavesPreferenceValuesFreeForm() throws {
        let config = try loadFixture(fixtureReplacing(#""tile-type": "directory-tile""#, with: #""tile-type": "directory-tile", "anything": {"goes": 1}"#))
        #expect(config.preferences.count == 22)
    }

    @Test func rejectsEmptyNames() {
        let cases = [
            (#""cursor-cli""#, #""""#, "homebrew.casks[4] must not be empty"),
            (#""vercel""#, #""""#, "homebrew.brews[9] must not be empty"),
            (#""name": "tailscale""#, #""name": """#, "homebrew.brews[8].name must not be empty"),
            (#""domain": "com.apple.HIToolbox""#, #""domain": """#, "preferences[6].domain must not be empty"),
            (#""default": {}"#, #""": {}"#, "hosts has an empty name"),
            (#""com.apple.dock": "Dock""#, #""com.apple.dock": """#, "restart.com.apple.dock must not be empty"),
            (#""linearis""#, #""""#, "bunGlobals[2] must not be empty"),
        ]
        for (original, replacement, message) in cases {
            #expect(loadError(fixtureReplacing(original, with: replacement)) == message)
        }
    }

    @Test func rejectsInvalidValues() {
        let cases = [
            (#""value": 3"#, #""value": null"#, "preferences[14].value must not contain null"),
            (#""value": []"#, #""value": [1, null]"#, "preferences[11].value must not contain null"),
            (#""key": "show-recents", "value": false"#, #""key": "show-recents""#, "preferences[13].value is required"),
            (#""source": "dotfiles/zsh/lib""#, #""source": "/etc/zshrc""#, "links[0].source must be relative to the config directory"),
            (#""target": "~/.ssh/config""#, #""target": ".ssh/config""#, "links[2].target must be absolute or start with ~/ or ${HOME}"),
            (#""path": "~/.oh-my-zsh""#, #""path": "$HOME/.oh-my-zsh""#, "clones[0].path must be absolute or start with ~/ or ${HOME}"),
            (#""SUNGHYUN_CURSOR_USAGE_PUSH": "0""#, #""CURSOR-PUSH": "0""#, "hosts.twelvecomputer.env: \"CURSOR-PUSH\" is not a shell variable name"),
        ]
        for (original, replacement, message) in cases {
            #expect(loadError(fixtureReplacing(original, with: replacement)) == message)
        }
    }

    @Test func resolvesTheCurrentHost() throws {
        let config = try loadFixture()
        let twelve = config.host(named: "twelvecomputer")
        #expect(twelve.key == "twelvecomputer")
        #expect(twelve.casks.count == 28)
        #expect(Array(twelve.casks.suffix(2)) == ["okta-verify", "openvpn-connect"])
        #expect(twelve.brews.count == 12)
        #expect(twelve.env == ["SUNGHYUN_CURSOR_USAGE_PUSH": "0", "SUNGHYUN_WORKSPACE": "/Users/sc/Developer/TwelveLabs"])
        #expect(twelve.names == [.computerName: "Twelvecomputer", .hostName: "twelvecomputer", .localHostName: "twelvecomputer"])
        #expect(twelve.authorizedKeys?.count == 1)

        let aura = config.host(named: "auracomputer")
        #expect(aura.key == "auracomputer")
        #expect(aura.casks.count == 26)
        #expect(aura.env.isEmpty)
        #expect(aura.names[.computerName] == "Auracomputer")

        let unknown = config.host(named: "Sunghyuns-MacBook-Pro")
        #expect(unknown.key == "default")
        #expect(unknown.names.isEmpty)
        #expect(unknown.authorizedKeys == nil)
        #expect(unknown.casks == config.homebrew.casks)
    }

    @Test func repoMachineConfigLoads() throws {
        let directory = repoConfigDirectory
        let config = try MachineConfig.load(from: directory.appending(path: "machine.json"), home: fixtureHome)
        #expect(!config.homebrew.brews.isEmpty)
        #expect(!config.homebrew.casks.isEmpty)
        #expect(!config.preferences.isEmpty)
        #expect(!config.links.isEmpty)
        #expect(!config.hosts.isEmpty)
        for link in config.links {
            #expect(FileManager.default.fileExists(atPath: directory.appending(path: link.source).path(percentEncoded: false)), "missing \(link.source)")
        }
    }

    @Test func unknownHostWithoutDefaultGetsNothingExtra() throws {
        let config = try loadFixture(fixtureReplacing(",\n    \"default\": {}", with: ""))
        let view = config.host(named: "Sunghyuns-MacBook-Pro")
        #expect(view.key == nil)
        #expect(view.names.isEmpty)
        #expect(view.env.isEmpty)
        #expect(view.brews.count == 12)
        #expect(config.host(named: nil).key == nil)
    }
}
