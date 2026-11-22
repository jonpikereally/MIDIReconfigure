import AppKit
import AppSupport
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var updater: Updater

    init(model: AppModel) {
        self.model = model
        self.updater = model.updater
    }

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

            Form {
                Section("App") {
                    Toggle("Show in Dock", isOn: $model.showInDock)
                        .help("Shows a Dock icon and the app menu. The main window opens at launch.")
                    Toggle("Show in menu bar", isOn: $model.showInMenuBar)
                        .help("Shows the menu bar icon for quick access to routing.")
                    if model.visibilityNotice != nil {
                        ErrorText(code: "APP-001", message: "One of Dock or menu bar must stay on.")
                    } else {
                        Text(visibilityDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Routing") {
                    Toggle("Route MIDI", isOn: Binding(get: { !model.isPaused }, set: { model.isPaused = !$0 }))
                        .disabled(!model.outputReady)
                    Picker("Default output channel", selection: $model.defaultOutputChannel) {
                        Text("Keep input").tag(nil as Int?)
                        ForEach(1...16, id: \.self) { channel in
                            Text("Channel \(channel)").tag(Optional(channel))
                        }
                    }
                    LabeledContent("Virtual output", value: AppModel.outputName)
                    LabeledContent("Inputs enabled") {
                        Text("\(model.sources.filter { model.enabledSourceIDs.contains($0.id) }.count) of \(model.sources.count)")
                    }
                    Button("Restart MIDI") { model.retryMIDI() }
                        .help("Restart the Core MIDI connection and reconnect enabled inputs.")
                }

                Section("Updates") {
                    LabeledContent("Installed version", value: AppModel.buildDescription)
                    updateStatus
                    Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                        .help("Checks at launch and every few hours.")
                    Toggle("Install updates automatically", isOn: $updater.installsAutomatically)
                        .disabled(!updater.checksAutomatically || !updater.canInstall)
                        .help("Installs a new version when the app launches. Updates never install in the middle of a session.")
                    Text(installNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Check for Updates") { updater.check() }
                            .disabled(isBusy)
                        if let release = updater.availableRelease {
                            Button("Install \(release.version.description) and Relaunch") {
                                updater.installAvailableUpdate()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!updater.canInstall || release.downloadURL == nil)
                        }
                        Spacer()
                        Link("Release history", destination: Updater.releasesPage)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var visibilityDescription: String {
        switch (model.showInDock, model.showInMenuBar) {
        case (true, true): "MIDI Reconfigure appears in the Dock and the menu bar."
        case (true, false): "MIDI Reconfigure appears in the Dock only. Click its Dock icon to open this window."
        default: "MIDI Reconfigure runs from the menu bar only. Use its menu bar icon to open this window."
        }
    }

    private var installNote: String {
        if !updater.canInstall {
            return "This copy isn’t a packaged app, so updates can be checked but not installed."
        }
        return "Automatic installs happen only at launch, so an update never restarts the app during a set."
    }

    private var isBusy: Bool {
        switch updater.phase {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updater.phase {
        case .idle:
            LabeledContent("Status", value: lastCheckedText ?? "Not checked yet")
        case .checking:
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                }
            }
        case .upToDate:
            LabeledContent("Status") {
                Label("Up to date", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            if let lastCheckedText { LabeledContent("Last checked", value: lastCheckedText) }
        case let .available(release):
            LabeledContent("Status") {
                Label("Version \(release.version.description) is available", systemImage: "arrow.down.circle")
                    .foregroundStyle(brandTint)
            }
            if !release.notes.isEmpty {
                ScrollView {
                    Text(release.notes)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
            if release.downloadURL == nil {
                ErrorText(code: "UPD-003", message: "This release has no app download attached.")
            }
        case let .downloading(release):
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Downloading \(release.version.description)…")
                }
            }
        case .installing:
            LabeledContent("Status", value: "Installing. The app will relaunch.")
        case let .failed(code, message):
            LabeledContent("Status") {
                ErrorText(code: code, message: message)
            }
        }
    }

    private var lastCheckedText: String? {
        updater.lastChecked.map { Self.dateFormat.string(from: $0) }
    }
}
