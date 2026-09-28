import SwiftUI

struct PetManagerView: View {
    @ObservedObject var preferences: PetPreferences
    @ObservedObject var library: PetModelLibrary
    let addPet: (String?, PetScope) -> Void
    let registerModel: () -> Void
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Desktop pets").font(.headline)
                        Spacer()
                        Menu("Add pet") {
                            ForEach(PetScope.allCases) { scope in
                                let builtin = builtinPet(for: scope)
                                Button("\(builtin.name) — \(scope.label)") {
                                    addPet(nil, scope)
                                }
                            }
                            if !library.models.isEmpty {
                                Divider()
                            }
                            ForEach(library.models) { model in
                                Button(model.manifest.displayName) { addPet(model.id, .everyone) }
                            }
                        }
                        .fixedSize()
                        .disabled(!preferences.canAddPet)
                    }
                    ForEach(preferences.pets) { pet in
                        PetRow(preferences: preferences, library: library, pet: pet)
                    }
                    Text("Up to \(PetPreferences.maximumPets) pets. A pet can follow all agents or only one of them. Each pet keeps its own model, position, and visibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Models").font(.headline)
                        Spacer()
                        Button {
                            library.reload()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Reload models")
                        .accessibilityLabel("Reload models")
                        Button("Register model…", action: registerModel)
                    }
                    ForEach(PetScope.allCases) { scope in
                        let builtin = builtinPet(for: scope)
                        ModelRow(
                            model: nil,
                            coat: coatDefinition(builtin.coat),
                            title: builtin.name,
                            subtitle: "Built in · \(scope.label)"
                        ) {}
                    }
                    ForEach(library.models) { model in
                        ModelRow(model: model, subtitle: model.manifest.description) {
                            remove(model)
                        }
                    }
                    Text(codexNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 640)
    }

    private var codexNote: String {
        let folder = library.codexDirectory.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "~/.codex/pets"
        return "Pets installed for Codex in \(folder) appear here automatically. Register a model to keep a copy in Amora."
    }

    private func remove(_ model: PetModel) {
        do {
            try library.remove(id: model.id)
            if library.model(id: model.id) == nil {
                preferences.clearModel(model.id)
            }
            message = nil
        } catch {
            message = "Could not remove \(model.manifest.displayName): \(error.localizedDescription)"
        }
    }
}

private struct PetRow: View {
    @ObservedObject var preferences: PetPreferences
    @ObservedObject var library: PetModelLibrary
    let pet: DesktopPet

    private var isActive: Bool { preferences.activePetID == pet.id }
    private var model: PetModel? { library.model(id: pet.modelID) }
    private var builtin: BuiltinPet { builtinPet(for: pet.scope) }
    private var displayName: String { petDisplayName(scope: pet.scope, modelName: model?.manifest.displayName) }

    var body: some View {
        HStack(spacing: 10) {
            PetModelThumbnail(model: model, coat: coatDefinition(builtin.coat))
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 108, alignment: .leading)
            Picker("Follows", selection: Binding(
                get: { pet.scope },
                set: { preferences.setScope($0, for: pet.id) }
            )) {
                ForEach(PetScope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            .accessibilityLabel("Who \(displayName) follows")
            Picker("Model", selection: Binding(
                get: { model?.id ?? "" },
                set: { preferences.setModel($0.isEmpty ? nil : $0, for: pet.id) }
            )) {
                Text(builtin.name).tag("")
                ForEach(library.models) { model in
                    Text(model.manifest.displayName).tag(model.id)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            .accessibilityLabel("Model for \(displayName)")
            Spacer(minLength: 8)
            Button(pet.isVisible ? "Hide" : "Show") {
                preferences.setVisible(!pet.isVisible, for: pet.id)
            }
            .accessibilityLabel("\(pet.isVisible ? "Hide" : "Show") \(displayName)")
            Button {
                preferences.setActive(pet.id)
            } label: {
                Image(systemName: isActive ? "star.fill" : "star")
            }
            .disabled(isActive)
            .help("Make active")
            .accessibilityLabel("Make \(displayName) active")
            Button {
                preferences.removePet(pet.id)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(!preferences.canRemovePet)
            .help("Remove pet")
            .accessibilityLabel("Remove \(displayName)")
        }
    }

    private var status: String {
        let visibility = isActive ? "Active" : (pet.isVisible ? "Visible" : "Hidden")
        return "\(pet.scope.label) · \(visibility)"
    }
}

private struct ModelRow: View {
    let model: PetModel?
    var coat: PetCoatDefinition = coatDefinition(.blueMerle)
    var title: String?
    let subtitle: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PetModelThumbnail(model: model, coat: coat)
            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? model?.manifest.displayName ?? "Amora")
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let model {
                Text(model.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                switch model.source {
                case .amora:
                    Button("Remove", action: onRemove)
                        .accessibilityLabel("Remove model \(model.manifest.displayName)")
                case .codex:
                    Text("From Codex")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
