//
//  CreateCollectionView.swift
//  romm
//
//  Created by Ilyas Hallak on 26.08.25.
//

import SwiftUI
import Observation

@MainActor
@Observable
class CreateCollectionViewModel {
    var name: String = ""
    var description: String = ""
    var isPublic: Bool = false
    var isCreating: Bool = false
    var error: String?
    
    private let createCollectionUseCase: CreateCollectionUseCase
    
    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.createCollectionUseCase = factory.makeCreateCollectionUseCase()
    }
    
    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }
    
    func createCollection() async -> Collection? {
        guard canCreate else { return nil }
        
        isCreating = true
        error = nil
        
        do {
            let data = CreateCollectionData(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                isPublic: isPublic,
                artworkURL: nil // TODO: Handle artwork later
            )
            
            let createdCollection = try await createCollectionUseCase.execute(data: data)
            isCreating = false
            return createdCollection
            
        } catch {
            isCreating = false
            self.error = error.localizedDescription
            return nil
        }
    }
    
    func reset() {
        name = ""
        description = ""
        isPublic = false
        error = nil
        isCreating = false
    }
}

struct CreateCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CreateCollectionViewModel()
    
    let onCollectionCreated: (Collection) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                collectionDetailsSection
                visibilitySection
                artworkSection
            }
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isCreating)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createCollection()
                    }
                    .disabled(!viewModel.canCreate || viewModel.isCreating)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                Text(viewModel.error ?? "")
            }
            .overlay {
                if viewModel.isCreating {
                    loadingOverlay
                }
            }
        }
    }
    
    private var collectionDetailsSection: some View {
        Section {
            TextField("Collection Name", text: $viewModel.name)
                .textContentType(.name)
            
            TextField("Description", text: $viewModel.description, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("Collection Details")
        } footer: {
            Text("Give your collection a name and optional description")
        }
    }
    
    private var visibilitySection: some View {
        Section {
            Toggle("Public Collection", isOn: $viewModel.isPublic)
        } header: {
            Text("Visibility")
        } footer: {
            Text("Public collections are visible to everyone. Private collections are only visible to you.")
        }
    }
    
    private var artworkSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                
                Text("Collection Artwork")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Coming Soon")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } header: {
            Text("Artwork")
        } footer: {
            Text("Collection artwork upload will be available in a future update")
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                LoadingView("Creating Collection...")
            }
            .padding(32)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private func createCollection() {
        Task {
            if let createdCollection = await viewModel.createCollection() {
                onCollectionCreated(createdCollection)
                dismiss()
            }
        }
    }
}

#Preview {
    CreateCollectionView { collection in
        print("Created collection: \(collection.name)")
    }
}
