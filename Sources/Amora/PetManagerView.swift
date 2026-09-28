import SwiftUI

struct PetManagerView: View {
    @ObservedObject var preferences: PetPreferences
    @ObservedObject var library: PetModelLibrary
    let addPet: (String?) -> Void
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
                            Button("Amora") { addPet(nil) }
                            if !library.models.isEmpty {
                                Divider()
                            }
                            ForEach(library.models) { model in
                                Button(model.manifest.displayName) { addPet(model.id) }
                            }
                        }
                        .fixedSize()
                        .disabled(!preferences.canAddPet)
                    }
                    ForEach(Array(preferences.pets.enumerated()), id: \.element.id) { index, pet in
                        PetRow(preferences: preferences, library: library, pet: pet, number: index + 1)
                    }
                    Text("Up to \(PetPreferences.maximumPets) pets. Each pet keeps its own model, position, and visibility.")
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
                        Button("Register model…", action: registerModel)
                    }
                    ModelRow(model: nil, subtitle: "Built in") {}
                    ForEach(library.models) { model in
                        ModelRow(model: model, subtitle: model.manifest.description) {
                            remove(model)
                        }
                    }
                    if library.models.isEmpty {
                        Text("Register a model in the Codex pet format to use it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .frame(width: 520)
    }

    private func remove(_ model: PetModel) {
        do {
            try library.remove(id: model.id)
            preferences.clearModel(model.id)
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
    let number: Int

    private var isActive: Bool { preferences.activePetID == pet.id }
    private var model: PetModel? { library.model(id: pet.modelID) }

    var body: some View {
        HStack(spacing: 10) {
            PetModelThumbnail(model: model)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pet \(number)")
                Text(isActive ? "Active" : (pet.isVisible ? "Visible" : "Hidden"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Picker("Model", selection: Binding(
                get: { model?.id ?? "" },
                set: { preferences.setModel($0.isEmpty ? nil : $0, for: pet.id) }
            )) {
                Text("Amora").tag("")
                ForEach(library.models) { model in
                    Text(model.manifest.displayName).tag(model.id)
                }
            }
            .labelsHidden()
            .frame(width: 140)
            .accessibilityLabel("Model for Pet \(number)")
            Button(pet.isVisible ? "Hide" : "Show") {
                preferences.setVisible(!pet.isVisible, for: pet.id)
            }
            .accessibilityLabel("\(pet.isVisible ? "Hide" : "Show") Pet \(number)")
            Button {
                preferences.setActive(pet.id)
            } label: {
                Image(systemName: isActive ? "star.fill" : "star")
            }
            .disabled(isActive)
            .help("Make active")
            .accessibilityLabel("Make Pet \(number) active")
            Button {
                preferences.removePet(pet.id)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(!preferences.canRemovePet)
            .help("Remove pet")
            .accessibilityLabel("Remove Pet \(number)")
        }
    }
}

private struct ModelRow: View {
    let model: PetModel?
    let subtitle: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PetModelThumbnail(model: model)
            VStack(alignment: .leading, spacing: 2) {
                Text(model?.manifest.displayName ?? "Amora")
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
                Button("Remove", action: onRemove)
                    .accessibilityLabel("Remove model \(model.manifest.displayName)")
            }
        }
    }
}
