import SwiftUI

struct SFTPDirectoryBrowserView: View {
    @State private var viewModel: SFTPDirectoryBrowserViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingCreateDirectory = false
    @State private var newDirectoryName = ""
    
    let onPathSelected: (String) -> Void
    private let romName: String?
    
    init(connection: SFTPConnection, romName: String? = nil, dependencyFactory: PDependencyFactory = DefaultDependencyFactory.shared, onPathSelected: @escaping (String) -> Void) {
        self._viewModel = State(wrappedValue: dependencyFactory.makeSFTPDirectoryBrowserViewModel(connection: connection))
        self.onPathSelected = onPathSelected
        self.romName = romName
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    if !viewModel.favoriteDirectories.isEmpty {
                        favoritesSection
                    }
                    
                    if let romName = romName {
                        compactRomInfo
                    }
                    
                    pathBreadcrumb
                    
                    if viewModel.isLoading {
                        ProgressView("Loading directory...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.directoryItems.isEmpty {
                        emptyDirectoryView
                    } else {
                        directoryList
                    }
                }
                
                // Floating Action Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            selectCurrentPath()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Select")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 34) // Account for safe area
                    }
                }
            }
            .navigationTitle("Browse Directory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Add to Favorites") {
                            viewModel.addToFavorites(viewModel.currentPath)
                        }
                        
                        Button("Create Directory") {
                            showingCreateDirectory = true
                        }
                        
                        if viewModel.canGoUp {
                            Button("Go to Parent") {
                                Task {
                                    await viewModel.goUp()
                                }
                            }
                        }
                        
                        Button("Go to Root") {
                            Task {
                                await viewModel.goToRoot()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                Text(viewModel.error ?? "")
            }
            .sheet(isPresented: $showingCreateDirectory) {
                createDirectorySheet
            }
        }
        .task {
            await viewModel.loadDirectory()
        }
    }
    
    private var compactRomInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "gamecontroller")
                .font(.caption)
                .foregroundColor(.accentColor)
            
            Text("Uploading: \(romName ?? "Unknown ROM")")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
    
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorites")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.favoriteDirectories, id: \.self) { favorite in
                        Button(action: {
                            Task {
                                await viewModel.navigateToFavorite(favorite)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                
                                Text(favorite == "/" ? "Root" : URL(fileURLWithPath: favorite).lastPathComponent)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                        .contextMenu {
                            Button("Remove from Favorites", role: .destructive) {
                                viewModel.removeFromFavorites(favorite)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    private var pathBreadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.currentPathComponents.enumerated()), id: \.offset) { index, component in
                    Button(component) {
                        Task {
                            await viewModel.navigateToPathComponent(at: index)
                        }
                    }
                    .foregroundColor(index == viewModel.currentPathComponents.count - 1 ? .primary : .blue)
                    .fontWeight(index == viewModel.currentPathComponents.count - 1 ? .semibold : .regular)
                    
                    if index < viewModel.currentPathComponents.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    private var directoryList: some View {
        List {
            if viewModel.canGoBack {
                Button(action: {
                    Task {
                        await viewModel.goBack()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Back")
                        Spacer()
                    }
                }
                .foregroundColor(.blue)
            }
            
            ForEach(viewModel.directories) { item in
                DirectoryItemRow(
                    item: item,
                    isFavorite: viewModel.favoriteDirectories.contains(item.path),
                    onTap: {
                        Task {
                            await viewModel.navigateToDirectory(item)
                        }
                    },
                    onSelect: {
                        onPathSelected(item.path)
                        dismiss()
                    },
                    onToggleFavorite: {
                        if viewModel.favoriteDirectories.contains(item.path) {
                            viewModel.removeFromFavorites(item.path)
                        } else {
                            viewModel.addToFavorites(item.path)
                        }
                    }
                )
            }
            
            if !viewModel.files.isEmpty {
                Section("Files") {
                    ForEach(viewModel.files) { file in
                        FileItemRow(item: file)
                    }
                }
            }
        }
    }
    
    private var emptyDirectoryView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Empty Directory")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("This directory contains no files or folders")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Select This Path") {
                selectCurrentPath()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var createDirectorySheet: some View {
        NavigationView {
            Form {
                Section("New Directory") {
                    TextField("Directory Name", text: $newDirectoryName)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle("Create Directory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingCreateDirectory = false
                        newDirectoryName = ""
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        Task {
                            await viewModel.createDirectory(name: newDirectoryName)
                            showingCreateDirectory = false
                            newDirectoryName = ""
                        }
                    }
                    .disabled(newDirectoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func selectCurrentPath() {
        onPathSelected(viewModel.currentPath)
        dismiss()
    }
}

struct DirectoryItemRow: View {
    let item: SFTPDirectoryItem
    let isFavorite: Bool
    let onTap: () -> Void
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onTap) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    
                    Text(item.name)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .swipeActions(edge: .leading) {
            Button("Select") {
                onSelect()
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(isFavorite ? "Unfavorite" : "Favorite") {
                onToggleFavorite()
            }
            .tint(isFavorite ? .orange : .yellow)
        }
        .contextMenu {
            Button("Select This Path") {
                onSelect()
            }
            
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                onToggleFavorite()
            }
        }
    }
}

struct FileItemRow: View {
    let item: SFTPDirectoryItem
    
    var body: some View {
        HStack {
            Image(systemName: "doc.fill")
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                
                if let size = item.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
    }
}

#Preview {
    SFTPDirectoryBrowserView(
        connection: SFTPConnection(
            name: "Test Server",
            host: "example.com",
            username: "user"
        ),
        dependencyFactory: DefaultDependencyFactory.shared
    ) { _ in }
}