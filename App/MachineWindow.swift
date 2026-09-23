import AppKit
import Observation
import SwiftUI
import AnaclastCore

@MainActor
enum MachineWindow {
    private static var window: NSWindow?
    private static let model = MachineModel(session: MachineSession(directory: ConfigStore.machineDirectory, home: MachineSession.currentHome))

    static func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.bringForward()
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: MachineView(model: model)))
        window.title = "Machine Config"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(width: 760, height: 680))
        window.center()
        return window
    }
}

@MainActor
@Observable
final class MachineModel {
    private(set) var plan: MachinePlan?
    private(set) var loadError: String?
    private(set) var log: [String] = []
    private(set) var summary: MachineSummary?
    private(set) var isPlanning = false
    private(set) var isApplying = false
    var isConfirming = false
    @ObservationIgnored let session: MachineSession

    init(session: MachineSession) {
        self.session = session
    }

    var isBusy: Bool { isPlanning || isApplying }

    func refresh() {
        guard !isBusy else { return }
        isPlanning = true
        Task {
            do {
                plan = try await session.plan(refreshDownloads: false)
                loadError = nil
            } catch {
                plan = nil
                loadError = String(describing: error)
            }
            isPlanning = false
        }
    }

    func requestApply() {
        guard let plan, !isBusy else { return }
        if plan.destructiveCount > 0 {
            isConfirming = true
        } else {
            apply(includeDestructive: false)
        }
    }

    func apply(includeDestructive: Bool) {
        guard let plan, !isBusy else { return }
        isApplying = true
        log = []
        summary = nil
        let (lines, continuation) = AsyncStream.makeStream(of: String.self)
        let applier = MachineApplier(home: session.home) { continuation.yield($0) }
        Task {
            for await line in lines { log.append(line) }
        }
        Task {
            summary = await applier.apply(plan, includeDestructive: includeDestructive)
            continuation.finish()
            isApplying = false
            refresh()
        }
    }
}

struct MachineView: View {
    @Bindable var model: MachineModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.plan.map { "\($0.steps.count) changes, \($0.destructiveCount) destructive" } ?? "Machine Config")
                        .font(.headline)
                    Text(model.plan.map(hostLine) ?? model.session.configURL.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button("Refresh", action: model.refresh)
                    .disabled(model.isBusy)
                Button("Apply", action: model.requestApply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || (model.plan?.steps.isEmpty ?? true))
            }
            .padding()
            Divider()
            PlanList(model: model)
            if !model.log.isEmpty || model.isApplying {
                Divider()
                LogView(lines: model.log)
            }
            if let summary = model.summary {
                Divider()
                Text("\(summary.succeeded) succeeded, \(summary.failed) failed, \(summary.skipped) skipped")
                    .font(.callout)
                    .foregroundStyle(summary.failed > 0 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .confirmationDialog("Apply changes?", isPresented: $model.isConfirming) {
            if let plan = model.plan {
                Button("Apply All, Including \(plan.destructiveCount) Destructive", role: .destructive) {
                    model.apply(includeDestructive: true)
                }
                Button("Apply \(plan.steps.count - plan.destructiveCount) Non-Destructive Only") {
                    model.apply(includeDestructive: false)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Destructive changes replace or remove existing items. Replaced files go to the Trash, and Homebrew removals uninstall packages.")
        }
    }

    private func hostLine(_ plan: MachinePlan) -> String {
        "Host \(plan.localHostName ?? "(unknown)"), using \(plan.host.map { "hosts.\($0)" } ?? "no host entry")"
    }
}

private struct PlanList: View {
    let model: MachineModel

    var body: some View {
        if let error = model.loadError {
            ContentUnavailableView("Cannot Load machine.json", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let plan = model.plan {
            if plan.categories.isEmpty {
                ContentUnavailableView("Up to Date", systemImage: "checkmark.circle", description: Text("This Mac matches machine.json."))
            } else {
                List {
                    ForEach(plan.categories, id: \.self) { category in
                        Section(category.description) {
                            ForEach(plan.stepIndices(in: category), id: \.self) { index in
                                StepRow(step: plan.steps[index])
                            }
                            ForEach(plan.notes(in: category), id: \.self) { note in
                                Label(note, systemImage: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } else {
            ProgressView("Checking this Mac")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StepRow: View {
    let step: MachineStep

    var body: some View {
        Label {
            Text(step.description)
                .textSelection(.enabled)
        } icon: {
            if step.isDestructive {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Destructive: replaces or removes an existing item")
            } else {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LogView: View {
    let lines: [String]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(lines.indices, id: \.self) { index in
                    Text(lines[index])
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(lines[index].hasPrefix("FAILED") ? .red : .primary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: 200)
    }
}
