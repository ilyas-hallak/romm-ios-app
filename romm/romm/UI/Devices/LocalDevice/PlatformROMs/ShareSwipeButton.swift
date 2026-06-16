import SwiftUI

struct ShareSwipeButton: View {
    @State private var viewModel: ShareROMViewModel

    init(rom: DownloadedROM, factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        _viewModel = State(initialValue: factory.makeShareROMViewModel(rom: rom))
    }

    var body: some View {
        Button {
            viewModel.prepareShare()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .tint(.blue)
        .sheet(item: $viewModel.shareSheetItem, onDismiss: viewModel.cleanupTemporaryFiles) { item in
            ShareSheet(activityItems: item.urls)
        }
        .alert("Files Not Found", isPresented: $viewModel.showFileNotFoundAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The ROM files could not be found on this device. They may have been deleted or moved.")
        }
    }
}

struct ShareSheetItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}
