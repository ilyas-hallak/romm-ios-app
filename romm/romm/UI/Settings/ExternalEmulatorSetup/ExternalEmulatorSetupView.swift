import SwiftUI

/// Walks the user through adding an emulator app: install it, understand how a
/// game gets there, point at its saves, then hand one over for real.
///
/// It exists because picking an app used to be a one-tap setting that left three
/// things unsaid. The worst of them was Manic, which cannot take a game from the
/// share sheet at all, so Play looked broken until you knew to paste.
struct ExternalEmulatorSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel = ExternalEmulatorSetupViewModel()
    @State private var externalPlay = ExternalPlayCoordinator()
    @State private var isPickingFolder = false

    /// Called when an app was added, so the settings list can refresh.
    let onFinished: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.stage {
                case .choosingApp: appChoiceList
                case .step(let step): stepContent(step)
                case .finished: finishedContent
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isPickingFolder,
                allowedContentTypes: [.folder]
            ) { result in
                if case .success(let url) = result { viewModel.grantFolder(url) }
            }
            .externalPlayHandoff(externalPlay)
        }
        // Coming back from the App Store is the only way the install step ends,
        // and nothing tells us it happened, so it is re-checked on return.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshInstallState() }
        }
    }

    private var navigationTitle: String {
        guard let emulator = viewModel.emulator else { return String(localized: "Add Emulator") }
        return emulator.emulator.displayName
    }

    // MARK: - Choosing

    private var appChoiceList: some View {
        List {
            Section {
                ForEach(viewModel.addableEmulators, id: \.self) { emulator in
                    Button {
                        viewModel.choose(emulator)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gamecontroller")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(emulator.emulator.displayName)
                                    .foregroundStyle(Color.primary)
                                if !viewModel.isInstalled(emulator) {
                                    Text("Not installed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("Which app")
            } footer: {
                Text("Games are handed to the app you pick. Its saves can be synced back to RomM.")
            }

            if viewModel.addableEmulators.isEmpty {
                Section {
                    Text("Every supported app has already been added.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private func stepContent(_ step: ExternalEmulatorSetupStep) -> some View {
        VStack(spacing: 0) {
            List {
                switch step {
                case .install: installStep
                case .handoff: handoffStep
                case .saveFolder: saveFolderStep
                case .testRun: testRunStep
                }
            }
            stepFooter(step)
        }
    }

    private var installStep: some View {
        Section {
            explanation(
                icon: "arrow.down.app",
                text: String(localized: "\(navigationTitle) is not on this device yet. Install it, then come back here.")
            )
            Button("Open the App Store") { viewModel.openAppStore() }
        } header: {
            Text(ExternalEmulatorSetupStep.install.title)
        } footer: {
            Text("This step finishes by itself once the app is installed.")
        }
    }

    private var handoffStep: some View {
        Section {
            explanation(
                icon: "square.and.arrow.up",
                text: viewModel.emulator?.emulator.handoffExplanation ?? ""
            )
        } header: {
            Text(ExternalEmulatorSetupStep.handoff.title)
        }
    }

    private var saveFolderStep: some View {
        Section {
            explanation(
                icon: "folder",
                text: String(localized: "Pick this app's folder in Files so its saves can be read. Nothing is written to it.")
            )
            Button("Choose Folder…") { isPickingFolder = true }
            if let scan = viewModel.folderScan {
                scanResult(scan)
            }
        } header: {
            Text(ExternalEmulatorSetupStep.saveFolder.title)
        } footer: {
            Text("You can do this later from the sync screen.")
        }
    }

    private func scanResult(_ scan: ExternalSaveScan) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: scan.matched.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(scan.matched.isEmpty ? Color.orange : Color.green)
            if scan.matched.isEmpty {
                // Saying which of the two went wrong, because they need
                // opposite fixes: a wrong folder versus saves for games that
                // are not on this device.
                Text(scan.isEmpty
                     ? String(localized: "No saves in that folder. It may be the wrong one.")
                     : String(localized: "\(scan.unmatchedFileNames.count) saves found, but none for games you have here."))
            } else {
                Text("Found \(scan.matched.count) saves for games you have.")
            }
        }
        .font(.callout)
    }

    private var testRunStep: some View {
        Section {
            explanation(
                icon: "play.circle",
                text: String(localized: "Hand a game over once to see it work. Nothing is changed on the server.")
            )
            if let result = viewModel.testResult {
                testResultRow(result)
            }
            if viewModel.testableROMs.isEmpty {
                Text("Download a game first to try this.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.testableROMs.prefix(8)) { rom in
                    Button(rom.name) { testHandoff(rom) }
                }
            }
        } header: {
            Text(ExternalEmulatorSetupStep.testRun.title)
        }
    }

    private func testResultRow(_ result: ExternalEmulatorSetupViewModel.TestResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            switch result {
            case .handedOver(let name):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                Text("\(name) was handed over.")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                Text(message)
            }
        }
        .font(.callout)
    }

    private func testHandoff(_ rom: DownloadedROM) {
        Task {
            // The target is not the saved one yet, since setup has not finished,
            // so the coordinator is pointed at the app being set up.
            guard let emulator = viewModel.emulator else { return }
            externalPlay.overrideTarget(.external(emulator))
            let handled = await externalPlay.play(romId: rom.id)
            if let error = externalPlay.errorMessage {
                viewModel.recordTestResult(.failed(error))
                externalPlay.errorMessage = nil
            } else if handled {
                viewModel.recordTestResult(.handedOver(romName: rom.name))
            }
        }
    }

    // MARK: - Finishing

    private var finishedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.green)
            Text("\(navigationTitle) is ready")
                .font(.title3.weight(.semibold))
            Text("Play now opens games there.")
                .foregroundStyle(.secondary)
            Button("Done") {
                onFinished()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared pieces

    private func explanation(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
        }
    }

    private func stepFooter(_ step: ExternalEmulatorSetupStep) -> some View {
        HStack(spacing: 12) {
            // Where the user is, because four steps without a count feel
            // open-ended, and the install step can drop out so the total is
            // not something they can assume.
            if let position = stepPosition(step) {
                Text("Step \(position.current) of \(position.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if step.isSkippable {
                Button("Skip") { viewModel.skipCurrentStep() }
            }
            Button(isLastStep(step) ? "Finish" : "Continue") { viewModel.advance() }
                .buttonStyle(.borderedProminent)
                .disabled(step == .install && !isInstalledNow)
        }
        .padding()
        .background(.bar)
    }

    private func stepPosition(_ step: ExternalEmulatorSetupStep) -> (current: Int, total: Int)? {
        guard let steps = viewModel.plan?.steps, let index = steps.firstIndex(of: step) else { return nil }
        return (index + 1, steps.count)
    }

    private var isInstalledNow: Bool {
        guard let emulator = viewModel.emulator else { return false }
        return viewModel.isInstalled(emulator)
    }

    private func isLastStep(_ step: ExternalEmulatorSetupStep) -> Bool {
        viewModel.plan?.steps.last == step
    }
}
