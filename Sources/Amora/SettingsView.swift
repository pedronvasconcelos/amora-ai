import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Integrations")
                        .font(.headline)
                    ForEach(model.rows) { row in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                Text(row.installed ? "Installed" : "Not installed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Button(row.installed ? "Remove" : "Install") {
                                model.setInstalled(!row.installed, for: row.id)
                            }
                            .accessibilityLabel("\(row.installed ? "Remove" : "Install") \(row.name)")
                        }
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("General")
                        .font(.headline)
                    Toggle("Launch at login", isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    if !model.launchAtLoginRegistersNow {
                        Text("Saved on this Mac. Amora opens at login once it is installed as an app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(model.statusIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
