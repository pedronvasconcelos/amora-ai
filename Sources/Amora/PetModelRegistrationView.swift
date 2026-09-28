import AppKit
import SwiftUI

struct PetModelRegistrationView: View {
    @ObservedObject var library: PetModelLibrary
    let onRegistered: (PetModel) -> Void
    @State private var draft: PetModelDraft?
    @State private var message: String?
    @State private var isTargeted = false
    @State private var previewAnimation: PetAnimation = .idle

    private var isReplacing: Bool {
        draft.map { library.contains(id: $0.manifest.id) } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Register a pet model").font(.headline)
                Text("Use the Codex custom pet format: a pet.json manifest and a transparent spritesheet with 8 columns of 192×208 cells. Version 1 is 1536×1872; version 2 is 1536×2288.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            dropZone

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let draft {
                preview(draft)
            }

            HStack {
                Spacer()
                Button("Clear", action: reset)
                    .disabled(draft == nil && message == nil)
                Button(isReplacing ? "Replace model" : "Register model", action: register)
                .keyboardShortcut(.defaultAction)
                .disabled(draft == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 28))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text("Drop pet.json and spritesheet.webp here")
            Text("or the folder that contains them")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Choose files…", action: chooseFiles)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            inspect(urls)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop zone for pet.json and spritesheet")
    }

    private func preview(_ draft: PetModelDraft) -> some View {
        HStack(alignment: .top, spacing: 16) {
            PetSpriteFigure(sprite: draft.sprite, animation: previewAnimation, reduceMotion: false)
                .padding(8)
                .frame(width: 120, height: 130)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.manifest.displayName).font(.title3.weight(.semibold))
                Text(draft.manifest.description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("id \(draft.manifest.id) · version \(draft.manifest.spriteVersion)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Picker("Animation", selection: $previewAnimation) {
                    ForEach(PetAnimation.allCases) { animation in
                        Text("\(animation.name) (\(draft.sprite.frames(for: animation).count))").tag(animation)
                    }
                }
                .frame(width: 240)
                if library.contains(id: draft.manifest.id) {
                    Text("A model with this id is already registered. Registering replaces it.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose pet.json and the spritesheet, or the folder that contains them."
        if panel.runModal() == .OK {
            inspect(panel.urls)
        }
    }

    private func inspect(_ urls: [URL]) {
        do {
            draft = try PetModelImporter.inspect(urls)
            message = nil
            previewAnimation = .idle
        } catch {
            draft = nil
            message = error.localizedDescription
        }
    }

    private func register() {
        guard let draft else { return }
        do {
            let model = try library.register(draft)
            reset()
            onRegistered(model)
        } catch {
            message = "Could not register \(draft.manifest.displayName): \(error.localizedDescription)"
        }
    }

    private func reset() {
        draft = nil
        message = nil
        previewAnimation = .idle
    }
}
