import SwiftUI

/// Turns this phone into the second player's pad for a game running on another
/// one. Reachable from Settings and from the login screen, since playing along
/// needs no account of its own.
struct RemoteControllerView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = RemoteControllerViewModel()

    var body: some View {
        Group {
            if viewModel.isPlaying {
                padScreen
            } else {
                hostPicker
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear {
            viewModel.stop()
            OrientationLock.set([.portrait, .landscapeLeft, .landscapeRight])
        }
        .onChange(of: viewModel.isPlaying) { _, isPlaying in
            applyOrientationLock(isPlaying: isPlaying)
        }
    }

    // MARK: - Playing

    private var padScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RemoteGamepadView { button, pressed in
                viewModel.setButton(button, pressed: pressed)
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Leave") { viewModel.disconnect() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Spacer()
                    if let hostName = viewModel.hostName {
                        Label(hostName, systemImage: "wifi")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                Spacer()
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Picking a host

    private var hostPicker: some View {
        NavigationStack {
            List {
                Section {
                    if viewModel.hosts.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Looking for a game on this network")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        ForEach(viewModel.hosts) { host in
                            Button {
                                viewModel.connect(to: host)
                            } label: {
                                HStack {
                                    Image(systemName: "iphone.gen3")
                                    Text(host.name)
                                    Spacer()
                                    if viewModel.hostName == host.name {
                                        ProgressView()
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Games nearby")
                } footer: {
                    Text("On the other phone, switch Second Controller on in Settings and start a game. Both phones have to be on the same Wi-Fi.")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Play as Controller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Orientation

    /// The pad only reads as a gamepad sideways, so portrait is locked out for
    /// as long as this phone is one. A phone already held sideways keeps the
    /// side it is on, forcing one would flip it out of the player's hands.
    private func applyOrientationLock(isPlaying: Bool) {
        guard isPlaying else {
            OrientationLock.set([.portrait, .landscapeLeft, .landscapeRight])
            return
        }
        let isHeldSideways = OrientationLock.currentOrientation?.isLandscape ?? false
        OrientationLock.set(
            [.landscapeLeft, .landscapeRight],
            rotateTo: isHeldSideways ? nil : .landscapeRight
        )
    }
}
