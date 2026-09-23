import Foundation
import Testing
@testable import AnaclastCore

let configDirectory = "/Users/someone/Developer/anaclast/config"
let nixStore = "/nix/store/9sd0bizr898a9zkvxv9brafg42hzpadk-home-manager-files"

let checkStderr = """
Warning: Calling `preflight` is deprecated! Use `preflight_steps` instead.
Please report this issue to the parallel-web/homebrew-tap tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
  /opt/homebrew/Library/Taps/parallel-web/homebrew-tap/Casks/parallel-cli.rb:31

brew bundle can't satisfy your Brewfile's dependencies.
→ Cask codexbar needs to be installed or updated.
→ Formula mole needs to be installed or updated.
→ Formula playwright-cli needs to be installed or updated.
→ Formula pscale needs to be installed or updated.
→ Formula stripe-cli needs to be installed or updated.
→ Formula vercel needs to be installed or updated.
Satisfy missing dependencies with `brew bundle install`.

"""

let cleanupStdout = """
Would uninstall casks:
balenaetcher
Would uninstall formulae:
swiftformat
libpng
Would `brew cleanup`:
Would remove: /Users/someone/Library/Caches/Homebrew/Cask/codexbar--0.60.4.zip (70.5MB)
Would remove (empty directory): /opt/homebrew/lib/gio
Run `brew bundle cleanup --force` to make these changes.

"""

let bunListing = """
/Users/someone/.bun/install/global node_modules (1250)
├── @linqapp/cli@2.6.0
├── agent-slack@0.9.3
├── linearis@2026.8.0
├── mcporter@0.13.7
├── mint@4.2.784
├── starter-cli@0.1.4
└── toolkit-cli@1.67.0

"""

let disabledServices = """
	disabled services = {
		"com.adguard.mac.adguard.helper" => enabled
		"com.apple.CSCSupportd" => disabled
		"com.apple.ftpd" => disabled
		"com.openssh.sshd" => disabled
		"org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon" => enabled
		"homebrew.mxcl.tailscale" => enabled
	}

"""

let nixSudoLocal = """
auth       optional       /nix/store/2xlg1fpzmy1vwbprr16lgmavj7i27zp3-pam_reattach-1.3/lib/pam/pam_reattach.so
auth       sufficient     pam_tid.so
auth       sufficient     /nix/store/7v7nym8yypbdsqw25ry654alb64mm1rs-pam-watchid-2-unstable-2024-12-24/lib/pam_watchid.so

"""

let planDate = Date(timeIntervalSince1970: 1_790_138_112)
let planBackup = "/etc/pam.d/sudo_local.anaclast-backup-20260923T043512Z"

var liveDownloadsTile: [String: Any] {[
    "GUID": 268123749,
    "tile-data": [
        "arrangement": 1,
        "book": Data(repeating: 0x62, count: 668),
        "displayas": 0,
        "file-data": ["_CFURLString": "file:///Users/someone/Downloads/", "_CFURLStringType": 15] as [String: Any],
        "file-label": "Downloads",
        "file-mod-date": 260781401798699,
        "file-type": 2,
        "is-beta": false,
        "parent-mod-date": 91886107850772,
        "preferreditemsize": -1,
        "showas": 0,
    ] as [String: Any],
    "tile-type": "directory-tile",
]}

var liveDesktopViewSettings: [String: Any] {[
    "IconViewSettings": [
        "arrangeBy": "grid", "backgroundColorBlue": 1.0, "backgroundColorGreen": 1.0, "backgroundColorRed": 1.0, "backgroundType": 0,
        "gridOffsetX": 0.0, "gridOffsetY": 0.0, "gridSpacing": 54.0, "iconSize": 64.0, "labelOnBottom": false,
        "showIconPreview": true, "showItemInfo": true, "textSize": 12.0, "viewOptionsVersion": 1,
    ] as [String: Any],
]}

struct FakeProbe: MachineProbe {
    var names: [MachineConfig.HostNameKind: String] = [.computerName: "Homecomputer", .hostName: "homecomputer", .localHostName: "homecomputer"]
    var brewMissing = false
    var check = CommandOutput(status: 1, stdout: "", stderr: checkStderr)
    var cleanup = CommandOutput(status: 1, stdout: cleanupStdout, stderr: "")
    var bun: CommandOutput? = CommandOutput(status: 0, stdout: bunListing, stderr: "")
    var disabled = CommandOutput(status: 0, stdout: disabledServices, stderr: "")
    var preferences: [String: Any] = [
        "NSGlobalDomain/com.apple.keyboard.fnState": false,
        "NSGlobalDomain/AppleTemperatureUnit": "Celsius",
        "NSGlobalDomain/AppleMeasurementUnits": "Centimeters",
        "NSGlobalDomain/AppleMetricUnits": 1,
        "NSGlobalDomain/AppleMenuBarVisibleInFullscreen": false,
        "com.apple.HIToolbox/AppleFnUsageType": 2,
        "com.apple.menuextra.clock/ShowDate": 2,
        "com.apple.finder/ShowPathbar": true,
        "com.apple.finder/DesktopViewSettings": liveDesktopViewSettings,
        "com.apple.dock/persistent-apps": [Any](),
        "com.apple.dock/persistent-others": [liveDownloadsTile],
        "com.apple.dock/show-recents": false,
        "com.apple.controlcenter/AutoHideMenuBarOption": 0,
        "com.apple.TextInputMenu/visible": true,
        "com.apple.systemuiserver/NSStatusItem Visible com.apple.menuextra.TimeMachine": true,
        "com.apple.systemuiserver/menuExtras": [Any](),
        "com.apple.Siri/StatusMenuVisible/currentHost": false,
    ]
    var states: [String: FileState] = [
        "/Users/someone/.oh-my-zsh": .directory,
        "\(configDirectory)/dotfiles/zsh/lib": .directory,
        "\(configDirectory)/dotfiles/zsh/rc": .directory,
        "\(configDirectory)/dotfiles/cursor/User/keybindings.json": .file,
        "/Users/someone/.config/zsh/lib": .link("\(nixStore)/.config/zsh/lib"),
        "/Users/someone/.config/zsh/rc": .link("\(configDirectory)/dotfiles/zsh/rc"),
        "/Users/someone/Library/Application Support/Cursor/User/keybindings.json": .file,
        "/etc/pam.d/sudo_local": .link("/etc/static/pam.d/sudo_local"),
    ]
    var files: [String: String] = ["/etc/pam.d/sudo_local": nixSudoLocal]

    func hostNames() async throws -> [MachineConfig.HostNameKind: String] { names }

    func brewBundle(_ arguments: [String], brewfile: String) async throws -> CommandOutput {
        if brewMissing { throw MachineError("/opt/homebrew/bin/brew is not installed") }
        return arguments.first == "check" ? check : cleanup
    }

    func bunGlobals() async throws -> CommandOutput? { bun }
    func launchdDisabledServices() async throws -> CommandOutput { disabled }

    func preference(domain: String, key: String, currentHost: Bool) -> Any? {
        preferences["\(domain)/\(key)\(currentHost ? "/currentHost" : "")"]
    }

    func state(of path: String) -> FileState { states[path] ?? .missing }
    func contents(of path: String) -> String? { files[path] }
}

func makePlan(_ probe: FakeProbe = FakeProbe(), config: MachineConfig? = nil, refreshDownloads: Bool = false) async throws -> MachinePlan {
    try await MachinePlan.make(config: config ?? loadFixture(), configDirectory: configDirectory, home: fixtureHome, refreshDownloads: refreshDownloads, now: planDate, probe: probe)
}

func shell(_ script: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", script]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "sh exited \(process.terminationStatus) for \(script)")
    return String(decoding: data, as: UTF8.self)
}

@Suite struct MachinePlanTests {
    @Test func plansEverySection() async throws {
        let plan = try await makePlan()
        #expect(plan.host == "homecomputer")
        #expect(plan.steps.map(\.description) == [
            "Cask codexbar needs to be installed or updated.",
            "Formula mole needs to be installed or updated.",
            "Formula playwright-cli needs to be installed or updated.",
            "Formula pscale needs to be installed or updated.",
            "Formula stripe-cli needs to be installed or updated.",
            "Formula vercel needs to be installed or updated.",
            "Uninstall casks: balenaetcher",
            "Uninstall formulae: swiftformat",
            "Uninstall formulae: libpng",
            "Pull /Users/someone/.oh-my-zsh (fast-forward only)",
            "Download resend-cli to /Users/someone/.local/bin/resend",
            "Install bun global ntn",
            "Replace /Users/someone/.config/zsh/lib (a link to \(nixStore)/.config/zsh/lib) with a link to \(configDirectory)/dotfiles/zsh/lib",
            "Replace /Users/someone/Library/Application Support/Cursor/User/keybindings.json (a file) with a link to \(configDirectory)/dotfiles/cursor/User/keybindings.json",
            "Write /Users/someone/.config/zsh/host.zsh",
            "Write /Users/someone/.ssh/authorized_keys",
            "NSGlobalDomain _HIHideMenuBar: (unset) -> false",
            "NSGlobalDomain AppleMenuBarVisibleInFullscreen: false -> true",
            "com.apple.finder ShowHardDrivesOnDesktop: (unset) -> true",
            "com.apple.finder ShowStatusBar: (unset) -> true",
            "com.apple.controlcenter AutoHideMenuBarOption: 0 -> 3",
            "com.apple.TextInputMenu visible: true -> false",
            "com.apple.TextInputMenuAgent NSStatusItem VisibleCC Item-0: (unset) -> false",
            "com.apple.systemuiserver NSStatusItem VisibleCC com.apple.menuextra.TimeMachine: (unset) -> false",
            "com.apple.systemuiserver NSStatusItem Visible com.apple.menuextra.TimeMachine: true -> false",
            "Restart Finder for com.apple.finder",
            "Restart SystemUIServer for com.apple.systemuiserver",
            "Replace /etc/pam.d/sudo_local, keeping the old file as /etc/pam.d/sudo_local.anaclast-backup-20260923T043512Z",
            "Turn on Remote Login (com.openssh.sshd)",
        ])
        #expect(plan.steps.indices.filter { plan.steps[$0].isDestructive } == [6, 7, 8, 12, 13, 27])
        #expect(plan.destructiveCount == 6)
        #expect(plan.steps.map(\.category) == plan.steps.map(\.category).sorted())
        #expect(plan.notes == [MachinePlan.Note(category: .links, message: "\(configDirectory)/dotfiles/ssh/config does not exist, so /Users/someone/.ssh/config is not linked")])
        #expect(plan.categories == MachineStep.Category.allCases)
        #expect(plan.stepIndices(in: .restarts) == [25, 26])
    }

    @Test func generatedFilesCarryHostContent() async throws {
        let plan = try await makePlan()
        let files = plan.steps.compactMap { step -> GeneratedFile? in
            if case .file(let file, _) = step { file } else { nil }
        }
        #expect(files.map(\.path) == ["/Users/someone/.config/zsh/host.zsh", "/Users/someone/.ssh/authorized_keys"])
        #expect(files[0].contents == "")
        #expect(files[1].contents == "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIfIuLXlMZdhVBuskXewHup9R9abgg/ToF2ffewtFeNT\n")
        #expect(files[1].mode == 0o600)
        #expect(files[1].directoryMode == 0o700)
    }

    @Test func settledMachinePlansNothingButPulls() async throws {
        var probe = FakeProbe()
        probe.check = CommandOutput(status: 0, stdout: "The Brewfile's dependencies are satisfied.\n", stderr: "")
        probe.cleanup = CommandOutput(status: 0, stdout: "Would `brew cleanup`:\nWould remove (empty directory): /opt/homebrew/lib/gio\n", stderr: "")
        probe.bun = CommandOutput(status: 0, stdout: bunListing.replacing("├── mint@4.2.784", with: "├── mint@4.2.784\n├── ntn@0.22.4"), stderr: "")
        probe.disabled = CommandOutput(status: 0, stdout: disabledServices.replacing("\"com.openssh.sshd\" => disabled", with: "\"com.openssh.sshd\" => enabled"), stderr: "")
        for link in try loadFixture().links {
            let source = "\(configDirectory)/\(link.source)"
            probe.states[source] = .file
            probe.states[link.target] = .link(source)
        }
        probe.states["/Users/someone/.local/bin/resend"] = .file
        let authorizedKeys = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIfIuLXlMZdhVBuskXewHup9R9abgg/ToF2ffewtFeNT\n"
        let sudoLocal = "auth       optional       /opt/homebrew/lib/pam/pam_reattach.so\nauth       sufficient     pam_tid.so\n"
        for (path, contents) in ["/Users/someone/.config/zsh/host.zsh": "", "/Users/someone/.ssh/authorized_keys": authorizedKeys, "/etc/pam.d/sudo_local": sudoLocal] {
            probe.states[path] = .file
            probe.files[path] = contents
        }
        for (key, value) in [
            "NSGlobalDomain/_HIHideMenuBar": false, "NSGlobalDomain/AppleMenuBarVisibleInFullscreen": true,
            "com.apple.finder/ShowHardDrivesOnDesktop": true, "com.apple.finder/ShowStatusBar": true,
            "com.apple.TextInputMenu/visible": false, "com.apple.TextInputMenuAgent/NSStatusItem VisibleCC Item-0": false,
            "com.apple.systemuiserver/NSStatusItem VisibleCC com.apple.menuextra.TimeMachine": false,
            "com.apple.systemuiserver/NSStatusItem Visible com.apple.menuextra.TimeMachine": false,
        ] {
            probe.preferences[key] = value
        }
        probe.preferences["com.apple.controlcenter/AutoHideMenuBarOption"] = 3
        let plan = try await makePlan(probe)
        #expect(plan.steps.map(\.description) == ["Pull /Users/someone/.oh-my-zsh (fast-forward only)"])
        #expect(plan.notes.isEmpty)
        #expect(plan.destructiveCount == 0)
    }

    @Test func renamesAndRefreshesOnAnotherHost() async throws {
        var probe = FakeProbe()
        probe.names = [.computerName: "Someone's MacBook Pro", .localHostName: "workcomputer"]
        probe.states["/Users/someone/.oh-my-zsh"] = nil
        probe.states["/Users/someone/.local/bin/resend"] = .file
        probe.states["/Users/someone/.ssh/authorized_keys"] = .file
        probe.files["/Users/someone/.ssh/authorized_keys"] = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIfIuLXlMZdhVBuskXewHup9R9abgg/ToF2ffewtFeNT\n"
        let plan = try await makePlan(probe, refreshDownloads: true)
        #expect(plan.host == "workcomputer")
        let descriptions = plan.steps.map(\.description)
        #expect(descriptions.contains("Clone https://github.com/ohmyzsh/ohmyzsh.git into /Users/someone/.oh-my-zsh"))
        #expect(descriptions.contains("Download resend-cli again, replacing /Users/someone/.local/bin/resend"))
        #expect(descriptions.contains("Replace /Users/someone/.ssh/authorized_keys (a file)"))
        #expect(Array(descriptions.suffix(4)) == [
            "Replace /etc/pam.d/sudo_local, keeping the old file as /etc/pam.d/sudo_local.anaclast-backup-20260923T043512Z",
            "Set ComputerName: Someone's MacBook Pro -> Workcomputer",
            "Set HostName: (unset) -> workcomputer",
            "Turn on Remote Login (com.openssh.sshd)",
        ])
        let hostFile = try #require(plan.steps.lazy.compactMap { step -> GeneratedFile? in
            if case .file(let file, _) = step, file.path.hasSuffix("host.zsh") { file } else { nil }
        }.first)
        #expect(hostFile.contents == "export SAMPLE_USAGE_PUSH='0'\nexport SAMPLE_WORKSPACE='/Users/someone/Developer/Work'\n")
        #expect(plan.steps.filter(\.isDestructive).map(\.category) == [.homebrew, .homebrew, .homebrew, .downloads, .links, .links, .generatedFiles, .system])
    }

    @Test func restartsEachProcessOnceForItsChangedDomains() async throws {
        let config = try loadFixture(fixtureReplacing(#""com.apple.dock": "Dock","#, with: #""com.apple.dock": "Dock", "com.apple.controlcenter": "SystemUIServer","#))
        let plan = try await makePlan(config: config)
        let restarts = plan.stepIndices(in: .restarts).map { plan.steps[$0].description }
        #expect(restarts == ["Restart Finder for com.apple.finder", "Restart SystemUIServer for com.apple.controlcenter, com.apple.systemuiserver"])
    }

    @Test func missingToolsBecomeNotesOrFailingSteps() async throws {
        var probe = FakeProbe()
        probe.brewMissing = true
        probe.bun = nil
        probe.disabled = CommandOutput(status: 0, stdout: "\tdisabled services = {\n\t\t\"com.apple.ftpd\" => disabled\n\t}\n", stderr: "")
        let plan = try await makePlan(probe)
        #expect(plan.stepIndices(in: .homebrew).map { plan.steps[$0].description } == [
            "Install the Brewfile; it could not be checked: /opt/homebrew/bin/brew is not installed",
        ])
        #expect(plan.stepIndices(in: .bunGlobals).count == 8)
        #expect(plan.notes.map(\.message) == [
            "cleanup was not checked: /opt/homebrew/bin/brew is not installed",
            "bun is not installed, so every global is listed",
            "\(configDirectory)/dotfiles/ssh/config does not exist, so /Users/someone/.ssh/config is not linked",
            "Remote Login check skipped: launchctl print-disabled system does not list com.openssh.sshd",
        ])
        #expect(!plan.steps.contains { if case .remoteLogin = $0 { true } else { false } })
    }

    @Test func rendersBrewfiles() throws {
        let config = try loadFixture()
        let brewfile = Brewfile(homebrew: config.homebrew, host: config.host(named: "workcomputer"))
        let install = brewfile.install.split(separator: "\n")
        #expect(install.count == 3 + 12 + 28 + 2)
        #expect(Array(install.prefix(4)) == [#"tap "getsentry/tools""#, #"tap "inngest/tap""#, #"tap "parallel-web/tap""#, #"brew "agent-browser""#])
        #expect(install.contains(#"brew "tailscale", restart_service: :changed, start_service: true"#))
        #expect(install.filter { $0.contains("trusted") } == [
            #"brew "getsentry/tools/sentry", trusted: true"#,
            #"cask "inngest/tap/inngest", trusted: true"#,
            #"cask "parallel-web/tap/parallel-cli", trusted: true"#,
        ])
        #expect(install.contains(#"cask "logi-options+""#))
        #expect(install.contains(#"cask "openvpn-connect""#))
        #expect(Array(install.suffix(2)) == [#"mas "Amphetamine", id: 937984704"#, #"mas "KakaoTalk", id: 869223134"#])
        #expect(brewfile.cleanup == brewfile.install + "brew \"xcodegen\"\ncask \"hammerspoon\"\n")
        #expect(Brewfile.entry("brew", "oven-sh/bun/bun") == #"brew "oven-sh/bun/bun", trusted: true"#)
        #expect(Brewfile.entry("cask", "homebrew/cask") == #"cask "homebrew/cask""#)
        let qualified = try loadFixture(fixtureReplacing(#""name": "tailscale""#, with: #""name": "tailscale/tap/tailscale""#))
        #expect(Brewfile(homebrew: qualified.homebrew, host: qualified.host(named: nil)).install.contains(#"brew "tailscale/tap/tailscale", trusted: true, restart_service: :changed, start_service: true"#))
        #expect(Brewfile.quoted(##"we"ird\#{x}"##) == ##""we\"ird\\\#{x}""##)
    }

    @Test func readsBrewBundleCheck() throws {
        #expect(try Brewfile.missing(fromCheck: CommandOutput(status: 1, stdout: "", stderr: checkStderr)).count == 6)
        #expect(try Brewfile.missing(fromCheck: CommandOutput(status: 0, stdout: "The Brewfile's dependencies are satisfied.\n", stderr: "")).isEmpty)
        let failure = CommandOutput(status: 1, stdout: "", stderr: "Error: No available formula with the name \"definitely-not-a-formula\".\n")
        #expect(throws: MachineError("brew bundle check exited with status 1: Error: No available formula with the name \"definitely-not-a-formula\".")) {
            try Brewfile.missing(fromCheck: failure)
        }
    }

    @Test func readsBrewBundleCleanupSections() throws {
        let stdout = """
        Would uninstall casks:
        balenaetcher
        hammerspoon
        Would uninstall formulae:
        swiftformat
        xcodegen
        Would untap:
        inngest/tap
        Would uninstall Mac App Store apps:
        KakaoTalk (869223134)
        Would `brew cleanup`:
        Would remove: /Users/someone/Library/Caches/Homebrew/Cask/codexbar--0.60.4.zip (70.5MB)
        Would remove (empty directory): /opt/homebrew/lib/gio/modules
        Run `brew bundle cleanup --force` to make these changes.

        """
        let removals = try Brewfile.removals(fromCleanup: CommandOutput(status: 1, stdout: stdout, stderr: ""))
        #expect(removals.map { "\($0.heading)|\($0.name)" } == [
            "uninstall casks|balenaetcher", "uninstall casks|hammerspoon",
            "uninstall formulae|swiftformat", "uninstall formulae|xcodegen",
            "untap|inngest/tap",
            "uninstall Mac App Store apps|KakaoTalk (869223134)",
        ])
        #expect(try Brewfile.removals(fromCleanup: CommandOutput(status: 0, stdout: "Would `brew cleanup`:\nWould remove (empty directory): /opt/homebrew/lib/gio\n", stderr: "")).isEmpty)
        #expect(throws: MachineError.self) {
            try Brewfile.removals(fromCleanup: CommandOutput(status: 1, stdout: "", stderr: "Error: No available formula with the name \"x\".\n"))
        }
    }

    @Test func readsBunAndLaunchdListings() {
        #expect(MachinePlan.bunPackages(inListing: bunListing) == ["@linqapp/cli", "agent-slack", "linearis", "mcporter", "mint", "starter-cli", "toolkit-cli"])
        #expect(MachinePlan.packageName("@linqapp/cli@2.6.0") == "@linqapp/cli")
        #expect(MachinePlan.packageName("@linqapp/cli") == "@linqapp/cli")
        #expect(MachinePlan.packageName("linearis@2026.8.0") == "linearis")
        #expect(MachinePlan.remoteLoginEnabled(inDisabledServices: disabledServices) == false)
        #expect(MachinePlan.remoteLoginEnabled(inDisabledServices: disabledServices.replacing("\"com.openssh.sshd\" => disabled", with: "\"com.openssh.sshd\" => enabled")) == true)
        #expect(MachinePlan.remoteLoginEnabled(inDisabledServices: "\t\t\"com.openssh.sshd\" => true\n") == false)
        #expect(MachinePlan.remoteLoginEnabled(inDisabledServices: "\t\t\"com.openssh.sshd\" => false\n") == true)
        #expect(MachinePlan.remoteLoginEnabled(inDisabledServices: "\t\t\"com.apple.ftpd\" => disabled\n") == nil)
    }

    @Test func matchesPreferencesAsSubsets() throws {
        let config = try loadFixture()
        let desired = { (key: String) in config.preferences.first { $0.key == key }!.value }
        #expect(MachinePlan.matches(live: [liveDownloadsTile], desired: desired("persistent-others")))
        let fileData: [String: Any] = ["_CFURLString": "file:///Users/someone/Downloads", "_CFURLStringType": 15]
        let tile: [String: Any] = ["tile-data": ["file-data": fileData], "tile-type": "directory-tile"]
        #expect(!MachinePlan.matches(live: [liveDownloadsTile], desired: [tile]))
        #expect(!MachinePlan.matches(live: [liveDownloadsTile, liveDownloadsTile], desired: desired("persistent-others")))
        #expect(!MachinePlan.matches(live: [Any](), desired: desired("persistent-others")))
        #expect(MachinePlan.matches(live: liveDesktopViewSettings, desired: desired("DesktopViewSettings")))
        var moved = liveDesktopViewSettings
        moved["IconViewSettings"] = (liveDesktopViewSettings["IconViewSettings"] as! [String: Any]).merging(["gridSpacing": 60.0]) { $1 }
        #expect(!MachinePlan.matches(live: moved, desired: desired("DesktopViewSettings")))
        #expect(MachinePlan.matches(live: [Any](), desired: desired("persistent-apps")))
        #expect(!MachinePlan.matches(live: ["com.apple.menuextra.airport"], desired: desired("menuExtras")))
        #expect(!MachinePlan.matches(live: nil, desired: desired("_HIHideMenuBar")))
        #expect(MachinePlan.matches(live: 54, desired: 54.0))
        #expect(MachinePlan.matches(live: NSNumber(value: true), desired: desired("ShowPathbar")))
        #expect(!MachinePlan.matches(live: "54", desired: 54))
        #expect(!MachinePlan.matches(live: ["IconViewSettings": 1], desired: desired("DesktopViewSettings")))
    }

    @Test func rendersValuesOnOneLine() {
        #expect(MachinePlan.render(nil) == "(unset)")
        #expect(MachinePlan.render(NSNumber(value: false)) == "false")
        #expect(MachinePlan.render(54.0) == "54")
        #expect(MachinePlan.render(["tile-type": "directory-tile", "GUID": 7] as [String: Any]) == #"{GUID: 7, tile-type: "directory-tile"}"#)
        #expect(MachinePlan.render(Data(count: 668)) == "<668 bytes>")
        let long = MachinePlan.render([liveDownloadsTile])
        #expect(long.count == 160)
        #expect(long.hasSuffix("…"))
        #expect(!long.contains("\n"))
    }

    @Test func shellQuotingSurvivesTheShell() throws {
        let values = ["plain", "it's", "'", "$HOME `id` $(id) \\ \" !", "line one\nline two", "", "--flag", "ß한글"]
        for value in values {
            #expect(try shell("/usr/bin/printf '%s' \(value.shellQuoted)") == value)
        }
    }

    @Test func hostEnvironmentFileSourcesBack() throws {
        let env = ["SAMPLE_USAGE_PUSH": "0", "QUOTED": "it's $HOME", "MULTI": "a\nb"]
        let file = GeneratedFile.hostEnvironment(env, home: fixtureHome)
        #expect(file.path == "/Users/someone/.config/zsh/host.zsh")
        #expect(file.contents.split(separator: "\n").first == "export MULTI='a")
        let directory = FileManager.default.temporaryDirectory.appending(path: "anaclast-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "host.zsh")
        try Data(file.contents.utf8).write(to: url)
        let output = try shell(". \(url.path.shellQuoted); /usr/bin/printf '%s|%s|%s' \"$SAMPLE_USAGE_PUSH\" \"$QUOTED\" \"$MULTI\"")
        #expect(output == "0|it's $HOME|a\nb")
    }

    @Test func rootScriptQuotesEveryValue() throws {
        let contents = "auth       optional       /opt/homebrew/lib/pam/pam_reattach.so\nauth       sufficient     pam_tid.so\n# it's $(id)\n"
        let steps: [MachineStep] = [
            .sudoLocal(contents, replacing: true, backup: planBackup),
            .hostName(.computerName, from: "Someone's MacBook Pro", to: "Someone's \"Mac\" $(reboot)"),
            .hostName(.localHostName, from: nil, to: "workcomputer"),
            .remoteLogin,
        ]
        let script = RootScript.render(steps)
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == "#!/bin/sh")
        #expect(script.contains("/usr/sbin/scutil --set ComputerName 'Someone'\\''s \"Mac\" $(reboot)'\n/bin/echo anaclast-root-status 1 $?\n"))
        #expect(script.contains("/usr/sbin/scutil --set LocalHostName 'workcomputer'\n/bin/echo anaclast-root-status 2 $?\n"))
        #expect(script.contains("/bin/launchctl enable system/com.openssh.sshd && /bin/launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist\n/bin/echo anaclast-root-status 3 $?\n"))
        #expect(script.hasSuffix("exit 0\n"))
        let directory = FileManager.default.temporaryDirectory.appending(path: "anaclast-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "root.sh")
        try Data(script.utf8).write(to: url)
        _ = try shell("/bin/sh -n \(url.path.shellQuoted)")
        let printf = try #require(RootScript.command(for: steps[0])?.split(separator: " && ").first { $0.hasPrefix("/usr/bin/printf") })
        let redirect = try #require(printf.range(of: " > "))
        #expect(try shell(String(printf[..<redirect.lowerBound])) == contents)
    }

    @Test func readsRootStatuses() {
        let output = "anaclast-root-status 0 0\nscutil: invalid name\nanaclast-root-status 1 1\nanaclast-root-status 3 0\n"
        #expect(RootScript.statuses(in: output) == [0: 0, 1: 1, 3: 0])
        #expect(RootScript.statuses(in: "anaclast-root-status 0 0\ranaclast-root-status 1 0\r") == [0: 0, 1: 0])
    }

    @Test func readsPamModulePaths() {
        let contents = "# auth optional /opt/homebrew/lib/pam/commented.so\n  #auth sufficient /nix/commented.so\nauth\toptional\t/opt/homebrew/lib/pam/pam_reattach.so\nauth       sufficient     pam_tid.so\n\nauth sufficient /opt/homebrew/lib/pam/pam_reattach.so debug\naccount required\n"
        #expect(RootScript.modulePaths(in: contents) == ["/opt/homebrew/lib/pam/pam_reattach.so"])
        #expect(RootScript.modulePaths(in: nixSudoLocal) == [
            "/nix/store/2xlg1fpzmy1vwbprr16lgmavj7i27zp3-pam_reattach-1.3/lib/pam/pam_reattach.so",
            "/nix/store/7v7nym8yypbdsqw25ry654alb64mm1rs-pam-watchid-2-unstable-2024-12-24/lib/pam_watchid.so",
        ])
    }

    @Test func rootScriptWritesSudoLocalOnlyWhenEveryModuleIsAFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "anaclast-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory.appending(path: "folder.so"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let present = directory.appending(path: "present.so").path(percentEncoded: false)
        let linked = directory.appending(path: "linked.so").path(percentEncoded: false)
        let folder = directory.appending(path: "folder.so").path(percentEncoded: false)
        let missing = directory.appending(path: "it's-missing.so").path(percentEncoded: false)
        try Data().write(to: URL(fileURLWithPath: present))
        try FileManager.default.createSymbolicLink(atPath: linked, withDestinationPath: present)
        let unchanged = "is not a regular file, so /etc/pam.d/sudo_local is left unchanged"

        func checks(_ modules: [String]) throws -> String {
            let contents = modules.map { "auth       optional       \($0)\n" }.joined() + "auth       sufficient     pam_tid.so\n"
            let step = MachineStep.sudoLocal(contents, replacing: false, backup: planBackup)
            let command = try #require(RootScript.command(for: step))
            #expect(RootScript.render([step]).contains("\n\(command)\n/bin/echo anaclast-root-status 0 $?\n"))
            let write = try #require(command.range(of: " && { [ ! -e '/etc/pam.d/sudo_local' ]"))
            return try shell(String(command[..<write.lowerBound]) + "; /bin/echo \"status $?\"")
        }

        #expect(try checks([present, linked]) == "status 0\n")
        #expect(try checks([present, missing, folder]) == "\(missing) \(unchanged)\nstatus 1\n")
        #expect(try checks([linked, folder]) == "\(folder) \(unchanged)\nstatus 1\n")
        #expect(RootScript.command(for: .sudoLocal("auth       sufficient     pam_tid.so\n", replacing: false, backup: planBackup))?.hasPrefix("{ [ ! -e '/etc/pam.d/sudo_local' ]") == true)
    }

    @Test func refusesRemovingAFormulaThatInstallsASudoModule() throws {
        let prefix = FileManager.default.temporaryDirectory.appending(path: "anaclast-tests-\(UUID().uuidString)")
        let keg = prefix.appending(path: "Cellar/pam-reattach/1.3")
        try FileManager.default.createDirectory(at: keg.appending(path: "lib/pam"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefix.appending(path: "lib/pam"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: prefix) }
        let files = ["INSTALL_RECEIPT.json", "lib/pam/pam_reattach.so"].map { keg.appending(path: $0).path(percentEncoded: false) }
        for file in files { try Data().write(to: URL(fileURLWithPath: file)) }
        let module = prefix.appending(path: "lib/pam/pam_reattach.so").path(percentEncoded: false)
        try FileManager.default.createSymbolicLink(atPath: module, withDestinationPath: "../../Cellar/pam-reattach/1.3/lib/pam/pam_reattach.so")
        let sudoLocal = "auth       optional       \(module)\nauth       sufficient     pam_tid.so\n"

        #expect(RootScript.removalRefusal(installing: files, sudoLocal: sudoLocal) == "refused: /etc/pam.d/sudo_local loads \(module), which this formula installs, and sudo fails when a PAM module is missing")
        #expect(RootScript.removalRefusal(installing: files.prefix(1), sudoLocal: sudoLocal) == nil)
        #expect(RootScript.removalRefusal(installing: files, sudoLocal: "# auth optional \(module)\nauth sufficient pam_tid.so\n") == nil)
        #expect(RootScript.removalRefusal(installing: files, sudoLocal: nixSudoLocal) == nil)
        #expect(RootScript.removalRefusal(installing: files, sudoLocal: "") == nil)
    }

    @Test func removesOnlyConfirmedEntriesThatAreStillListed() async throws {
        var probe = FakeProbe()
        probe.cleanup = CommandOutput(status: 1, stdout: """
        Would uninstall casks:
        balenaetcher
        Would uninstall formulae:
        libpng
        freetype
        pcre2
        swiftformat
        Would untap:
        oven-sh/bun
        Would uninstall Mac App Store apps:
        Pages (409201541)
        Run `brew bundle cleanup --force` to make these changes.

        """, stderr: "")
        let plan = try await makePlan(probe)
        let removals = plan.stepIndices(in: .homebrew).filter { if case .brewRemove = plan.steps[$0] { true } else { false } }
        #expect(removals.count == 7)
        let afterInstall = try Brewfile.removals(fromCleanup: CommandOutput(status: 1, stdout: """
        Would uninstall casks:
        balenaetcher
        Would uninstall formulae:
        libpng
        freetype
        swiftformat
        watchman
        Would untap:
        oven-sh/bun
        Would uninstall Mac App Store apps:
        Pages (409201541)
        Run `brew bundle cleanup --force` to make these changes.

        """, stderr: ""))

        let (pending, skipped) = plan.removals(removals, stillListedIn: afterInstall)
        #expect(pending.map { plan.steps[$0].description } == [
            "Uninstall casks: balenaetcher",
            "Uninstall formulae: swiftformat",
            "Uninstall formulae: freetype",
            "Uninstall formulae: libpng",
            "Untap: oven-sh/bun",
            "Uninstall Mac App Store apps: Pages (409201541)",
        ])
        #expect(skipped.map { "\(plan.steps[$0.key])|\($0.value)" } == ["Uninstall formulae: pcre2|no longer removable, now required"])
        let nothingListed = plan.removals(removals, stillListedIn: [])
        #expect(nothingListed.pending.isEmpty)
        #expect(nothingListed.skipped.keys.sorted() == removals)
        #expect(Set(nothingListed.skipped.values) == ["no longer removable, now required"])
    }

    @Test func mapsEachCleanupEntryToItsOwnUninstall() throws {
        #expect(Brewfile.Removal(heading: "uninstall casks", name: "balenaetcher")?.brewArguments == ["uninstall", "--cask", "--force", "balenaetcher"])
        #expect(Brewfile.Removal(heading: "uninstall formulae", name: "getsentry/tools/sentry")?.brewArguments == ["uninstall", "--formula", "--force", "getsentry/tools/sentry"])
        #expect(Brewfile.Removal(heading: "untap", name: "inngest/tap")?.brewArguments == ["untap", "inngest/tap"])
        #expect(Brewfile.Removal(heading: "uninstall Mac App Store apps", name: "Odd (Name) (869223134)") == .appStore(id: 869223134))
        #expect(Brewfile.Removal(heading: "uninstall Mac App Store apps", name: "KakaoTalk") == nil)
        #expect(Brewfile.Removal(heading: "uninstall VSCode extensions", name: "ms-python.python") == nil)

        let appStore = MachineStep.brewRemove(heading: "uninstall Mac App Store apps", name: "KakaoTalk (869223134)")
        #expect(appStore.removal?.brewArguments == nil)
        #expect(RootScript.command(for: .brewRemove(heading: "uninstall formulae", name: "libpng")) == nil)
        let script = RootScript.render([appStore, .remoteLogin])
        #expect(script.contains("\nMAS_NO_AUTO_INDEX=1 SUDO_UID=\(getuid()) SUDO_GID=\(getgid()) /opt/homebrew/bin/mas uninstall 869223134\n/bin/echo anaclast-root-status 0 $?\n"))
        let directory = FileManager.default.temporaryDirectory.appending(path: "anaclast-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "root.sh")
        try Data(script.utf8).write(to: url)
        _ = try shell("/bin/sh -n \(url.path.shellQuoted)")
    }

    @Test func backupNamesAreTimestampedAndNeverOverwritten() throws {
        #expect(RootScript.backupPath(at: planDate) == planBackup)
        #expect(RootScript.backupPath(at: planDate.addingTimeInterval(1)) == "/etc/pam.d/sudo_local.anaclast-backup-20260923T043513Z")
        let directory = FileManager.default.temporaryDirectory.appending(path: "anaclast-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = directory.appending(path: "sudo_local")
        let backup = directory.appending(path: "sudo_local.anaclast-backup-20260923T043512Z")
        let command = try #require(RootScript.command(for: .sudoLocal("auth       sufficient     pam_tid.so\n", replacing: true, backup: planBackup)))
        let remove = try #require(command.range(of: " && /bin/rm -f "))
        let local = String(command[..<remove.lowerBound])
            .replacing(planBackup.shellQuoted, with: backup.path(percentEncoded: false).shellQuoted)
            .replacing(RootScript.sudoLocalPath.shellQuoted, with: live.path(percentEncoded: false).shellQuoted)
        try #require(!local.contains("/etc/"))
        let run = local + "; /bin/echo \"status $?\""

        #expect(try shell(run) == "status 0\n")
        #expect(!FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)))
        try Data("original\n".utf8).write(to: live)
        #expect(try shell(run) == "status 0\n")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "original\n")
        try Data("second\n".utf8).write(to: live)
        #expect(try shell(run) == "status 1\n")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "original\n")
    }
}
