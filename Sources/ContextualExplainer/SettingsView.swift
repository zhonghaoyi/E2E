import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var modelSearchText = ""

    var body: some View {
        let modelChoices = appState.filteredModels(matching: modelSearchText)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Model Settings")
                    .font(.title2.weight(.semibold))

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Provider", selection: Binding(
                        get: { appState.settings.provider },
                        set: { appState.selectProvider($0) }
                    )) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        Image(systemName: appState.settings.provider.systemImage)
                            .foregroundStyle(.secondary)
                        Text(appState.settings.provider.title)
                            .font(.headline)
                        Spacer()
                        Text(appState.settings.provider.baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        SecureField(appState.settings.provider.apiKeyHint, text: $appState.apiKey)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            appState.pasteAPIKeyFromClipboard()
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                        .help("Paste API key from clipboard")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("Search models", text: $modelSearchText)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                appState.refreshModels()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .disabled(appState.isLoadingModels)
                        }

                        Picker("Model", selection: $appState.settings.model) {
                            ForEach(modelChoices) { model in
                                Text(model.pickerTitle).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)

                        HStack(spacing: 8) {
                            if appState.isLoadingModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: appState.modelCatalogError == nil ? "checkmark.circle" : "exclamationmark.triangle")
                                    .foregroundStyle(appState.modelCatalogError == nil ? .green : .orange)
                            }

                            Text(appState.modelStatusText(matching: modelSearchText))
                                .font(.caption)
                                .foregroundStyle(appState.modelCatalogError == nil ? Color.secondary : Color.orange)
                                .lineLimit(2)
                        }
                    }

                    if appState.settings.provider == .deepSeek {
                        deepSeekThinkingSettings
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("History")
                        .font(.headline)

                    HStack(spacing: 8) {
                        TextField("History file path", text: $appState.settings.historyFilePath)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            appState.chooseHistoryFilePath()
                        } label: {
                            Label("Choose", systemImage: "folder")
                        }
                    }

                    HStack(spacing: 8) {
                        Text(appState.settings.historyFilePath.isEmpty ? "Using default file" : "Using custom file after Save")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            appState.useDefaultHistoryFilePath()
                        } label: {
                            Label("Default", systemImage: "arrow.uturn.backward")
                        }
                        .controlSize(.small)

                        Button {
                            appState.revealHistoryFilePath()
                        } label: {
                            Label("Show", systemImage: "magnifyingglass")
                        }
                        .controlSize(.small)
                    }

                    Text(appState.historyFileDisplayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(appState.settings.temperature, format: .number.precision(.fractionLength(2)))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $appState.settings.temperature, in: 0...1)

                    Stepper("Max tokens: \(appState.settings.maxTokens)", value: $appState.settings.maxTokens, in: 200...2000, step: 100)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Shortcut")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ShortcutMode.allCases) { mode in
                            Button {
                                appState.settings.shortcutMode = mode
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: appState.settings.shortcutMode == mode ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(appState.settings.shortcutMode == mode ? Color.accentColor : Color.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.title)
                                            .foregroundStyle(.primary)
                                        Text(mode.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: appState.hasAccessibilityPermission ? "checkmark.circle" : "lock.shield")
                            .foregroundStyle(appState.hasAccessibilityPermission ? .green : .secondary)
                        Text(appState.hasAccessibilityPermission ? "Accessibility permission is enabled." : "Global shortcuts need Accessibility permission.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            appState.refreshAccessibilityPermission()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)

                        Button {
                            appState.requestAccessibilityPermissionPrompt()
                            appState.openAccessibilitySettings()
                        } label: {
                            Label("Privacy", systemImage: "gear")
                        }
                        .controlSize(.small)
                    }
                }

                if appState.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(appState.statusMessage ?? "Testing...")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = appState.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let statusMessage = appState.statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                HStack {
                    Spacer()
                    Button {
                        appState.testConnection()
                    } label: {
                        Label("Test", systemImage: "network")
                    }

                    Button {
                        appState.saveSettings()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
        }
        .frame(width: 560, height: 620)
        .task {
            appState.loadModelsIfNeeded()
        }
    }

    private var deepSeekThinkingSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DeepSeek Thinking")
                .font(.headline)

            Picker("Thinking", selection: $appState.settings.deepSeekThinkingMode) {
                ForEach(DeepSeekThinkingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(appState.settings.deepSeekThinkingMode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Effort", selection: $appState.settings.deepSeekReasoningEffort) {
                ForEach(DeepSeekReasoningEffort.allCases) { effort in
                    Text(effort.title).tag(effort)
                }
            }
            .pickerStyle(.segmented)
            .disabled(appState.settings.deepSeekThinkingMode == .disabled)
        }
        .padding(.top, 4)
    }
}

#if DEBUG
#Preview {
    SettingsView(appState: AppState())
}
#endif
