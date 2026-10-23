import SwiftUI
import AVFoundation
import ServiceManagement
import WisprCore

enum Palette {
    static let background = Color(red: 0.967, green: 0.959, blue: 0.933)
    static let sidebar = Color(red: 0.932, green: 0.931, blue: 0.901)
    static let green = Color(red: 0.14, green: 0.34, blue: 0.25)
    static let ink = Color(red: 0.15, green: 0.19, blue: 0.16)
    static let muted = Color(red: 0.43, green: 0.46, blue: 0.42)
    static let line = Color(red: 0.84, green: 0.85, blue: 0.80)
}

struct Mark: View {
    var small = false
    var body: some View {
        HStack(spacing: small ? 2 : 3) {
            ForEach(0..<5) { index in
                Capsule().fill(Palette.green).frame(width: small ? 3 : 4, height: CGFloat([12, 22, 30, 22, 12][index]) * (small ? 0.65 : 1))
            }
        }.accessibilityHidden(true)
    }
}

struct PrimaryButton: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18).padding(.vertical, 11)
            .foregroundStyle(.white).background(destructive ? Color(red: 0.63, green: 0.28, blue: 0.20) : Palette.green)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("YOUR WORKSPACE  /  " + model.page.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(Palette.muted)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(model.modelReady ? Palette.green : Palette.muted).frame(width: 6, height: 6)
                        Text(model.modelReady ? "LOCAL MODEL READY" : "LOCAL FIRST")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                    }.foregroundStyle(Palette.green)
                }.padding(.bottom, 26)
                if let error = model.error {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.circle")
                        Text(error).font(.system(size: 12)).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
                    }.foregroundStyle(Color(red: 0.60, green: 0.25, blue: 0.16))
                        .padding(12).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.bottom, 16)
                }
                Group {
                    switch model.page {
                    case .dictate: DictationView(model: model)
                    case .models: ModelsView(model: model)
                    case .history: HistoryView(model: model)
                    case .settings: PreferencesView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background)
        }.foregroundStyle(Palette.ink).frame(minWidth: 940, minHeight: 700)

    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Mark()
                Text("wispr").font(.system(size: 23, weight: .medium, design: .rounded)) +
                Text("M").font(.system(size: 23, weight: .bold, design: .rounded)).foregroundColor(Palette.green)
            }.padding(.top, 18).padding(.bottom, 38)
            Text("A LITTLE SPACE TO SPEAK").font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(1).foregroundStyle(Palette.muted).padding(.bottom, 16)
            ForEach(Page.allCases, id: \.self) { page in
                Button { model.page = page } label: {
                    HStack(spacing: 11) {
                        Image(systemName: icon(page)).font(.system(size: 15)).frame(width: 18)
                        Text(page.rawValue).font(.system(size: 13, weight: model.page == page ? .semibold : .regular))
                        Spacer()
                        if model.page == page { Circle().fill(Palette.green).frame(width: 5, height: 5) }
                    }.padding(.horizontal, 12).padding(.vertical, 12)
                        .background(model.page == page ? Color.white.opacity(0.65) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.bottom, 5)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR SHORTCUT").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.4)
                HStack(spacing: 5) {
                    key("⌃"); key("⌥"); key("space")
                }
                Text("Speak from any text field.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                if !model.hotkeyAvailable { Text("Shortcut unavailable. Another app may be using it.").font(.caption).foregroundStyle(.red) }
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading).overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line))
            HStack(spacing: 7) {
                Image(systemName: "leaf").font(.system(size: 11))
                Text("ON YOUR MAC. IN YOUR VOICE.").font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(0.5)
            }.foregroundStyle(Palette.green).padding(.top, 25).padding(.bottom, 5)
        }.padding(20).frame(width: 205).frame(maxHeight: .infinity).background(Palette.sidebar)
    }
    private func key(_ value: String) -> some View {
        Text(value).font(.system(size: 12, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 5)
            .background(Palette.background).clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.line, lineWidth: 0.7))
    }
    private func icon(_ page: Page) -> String {
        switch page { case .dictate: return "waveform"; case .models: return "square.stack.3d.up"; case .history: return "clock"; case .settings: return "slider.horizontal.3" }
    }
}

struct DictationView: View {
    @ObservedObject var model: AppModel
    @State private var showOriginal = false
    private var displayedText: String { showOriginal ? model.rawTranscript : model.transcript }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                Text("A thought.\nBeautifully put.").font(.system(size: 38, weight: .regular, design: .serif)).lineSpacing(-2)
                Text("Speak naturally. Leave the finishing touches to wisprM.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
            }.padding(.bottom, 2)
            HStack(spacing: 12) {
                Label(model.settings.values.engine.rawValue, systemImage: "cpu")
                Text("·")
                Text(model.settings.values.style.rawValue)
                Spacer()
                Button("Import audio…", action: model.importAudio).buttonStyle(.plain)
                    .foregroundStyle(Palette.green).disabled(model.active || !model.modelReady)
                if model.settings.values.polish { Label("AI polish on", systemImage: "sparkles") }
                else { Text("Local cleanup") }
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.phaseTitle.uppercased()).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.2)
                    Spacer()
                    if model.recording { Text(String(format: "%02d:%02d", model.seconds / 60, model.seconds % 60)).monospacedDigit() }
                    else { Text("\(displayedText.split(whereSeparator: \.isWhitespace).count) words") }
                }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(18)
                Divider().overlay(Palette.line)
                ZStack(alignment: .topLeading) {
                    if displayedText.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(model.recording ? "Go on. We’re listening." : model.active ? "Your words are on their way…" : "Your next good thought starts here.")
                                .font(.system(size: 21, design: .serif)).foregroundStyle(Palette.muted.opacity(0.75))
                            Text(model.recording ? "Audio stays on this Mac. Finish to transcribe." : "Use the shortcut in another app to put your words directly into its text field.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted).frame(maxWidth: 360, alignment: .leading)
                        }.padding(20).allowsHitTesting(false)
                    }
                    TextEditor(text: Binding(get: { displayedText },
                                            set: { if !showOriginal { model.transcript = $0 } })).font(.system(size: 18, design: .serif))
                        .scrollContentBackground(.hidden).padding(14).opacity(displayedText.isEmpty ? 0.03 : 1)
                        .disabled(model.active || showOriginal).accessibilityLabel("Dictated text")
                }.frame(minHeight: 145, maxHeight: .infinity)
                if model.recording { LiveAudioMeter(levels: model.audioLevels).padding(.horizontal, 20).padding(.bottom, 15) }
                if model.phase == .transcribing || model.phase == .polishing {
                    ProgressView().controlSize(.small).padding(.horizontal, 20).padding(.bottom, 15)
                }
                HStack(spacing: 9) {
                    Button(action: model.toggleDictation) {
                        Label(model.recording ? "Finish dictation" : "Start dictation", systemImage: model.recording ? "stop.fill" : "mic.fill")
                    }.buttonStyle(PrimaryButton(destructive: model.recording))
                        .disabled((model.active && !model.recording) || model.runtime.busy || !model.modelReady)
                    if model.active {
                        Button("Cancel", action: model.cancel).buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 8)
                    }
                    Spacer()
                    if showOriginal || (!model.rawTranscript.isEmpty && model.rawTranscript != model.transcript) {
                        Button(showOriginal ? "Show polished" : "Show original") { showOriginal.toggle() }
                            .buttonStyle(.plain).font(.system(size: 11)).disabled(model.active)
                    }
                    Button { model.copy(showOriginal ? model.rawTranscript : model.transcript) } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(.plain).font(.system(size: 12)).disabled(displayedText.isEmpty)
                }.padding(16).background(Palette.sidebar.opacity(0.35))
            }.background(Color.white.opacity(0.65)).clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line, lineWidth: 0.8))
            if !model.modelReady {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 20)).foregroundStyle(Palette.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Make this Mac your listening space").font(.system(size: 12, weight: .medium))
                        Text("Download a local speech model to begin.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button("Set up models") { model.page = .models }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.green)
                }.padding(14).overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line))
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle").padding(.top, 1)
                Text(model.note).textSelection(.enabled)
            }.font(.system(size: 11)).foregroundStyle(Palette.muted).frame(minHeight: 28, alignment: .topLeading)
        }.onChange(of: model.transcriptGeneration) { _, _ in showOriginal = false }
    }
}

struct LiveAudioMeter: View {
    @ObservedObject var levels: AudioLevels
    var body: some View { AudioMeter(level: levels.level) }
}

struct AudioMeter: View {
    let level: Float
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<35) { index in
                Capsule().fill(Float(index) / 35 < max(0.025, level) ? Palette.green : Palette.line)
                    .frame(maxWidth: .infinity).frame(height: 5)
            }
        }.animation(.easeOut(duration: 0.08), value: level).accessibilityLabel("Microphone input level")
    }
}

struct ModelsView: View {
    @ObservedObject var model: AppModel
    private var preferences: Binding<Preferences> { Binding(get: { model.settings.values }, set: { model.settings.values = $0 }) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                title("A mind of its own.", subtitle: "Choose what listens. Choose what polishes. Keep both local.")
                sectionLabel("01  /  SPEECH RECOGNITION")
                HStack(spacing: 12) {
                    ForEach(SpeechEngine.allCases, id: \.self) { engine in
                        Button { model.settings.values.engine = engine } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: engine == .whisper ? "wind" : "bird")
                                    Spacer()
                                    Image(systemName: model.settings.values.engine == engine ? "checkmark.circle.fill" : "circle")
                                }.foregroundStyle(Palette.green)
                                Text(engine.rawValue).font(.system(size: 21, design: .serif))
                                Text(engine.detail).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                Text(engine == .whisper ? SpeechModelCatalog.bundled.whisperDownloadRange : SpeechModelCatalog.bundled.downloadSize(engine.defaultModel))
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(model.settings.values.engine == engine ? Palette.green.opacity(0.06) : Color.white.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.settings.values.engine == engine ? Palette.green : Palette.line))
                        }.buttonStyle(.plain)
                    }
                }.disabled(model.active || model.runtime.busy)
                if model.settings.values.engine == .whisper {
                    HStack(spacing: 8) {
                        Text("PRESETS").font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.muted)
                        ForEach(SpeechModelCatalog.whisperPresets, id: \.id) { preset in
                            let selected = model.settings.values.whisperModel == preset.id
                            Button { model.settings.values.whisperModel = preset.id } label: {
                                VStack(spacing: 3) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "checkmark.circle.fill").opacity(selected ? 1 : 0)
                                        Text(preset.name)
                                    }.font(.system(size: 11, weight: .semibold))
                                    Text(SpeechModelCatalog.bundled.downloadSize(preset.id))
                                        .font(.system(size: 9)).opacity(selected ? 0.9 : 1)
                                }
                                .foregroundStyle(selected ? Color.white : Palette.ink)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(selected ? Palette.green : Color.white.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Palette.green : Palette.line))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .help(SpeechModelCatalog.bundled.location(for: preset.id)?.path ?? preset.id)
                            .disabled(model.active || model.runtime.busy)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("Model ID or local model folder").font(.system(size: 12, weight: .medium))
                    TextField("Hugging Face model ID or absolute folder", text: Binding(
                        get: { model.settings.values.modelID }, set: { model.settings.values.modelID = $0 }))
                        .textFieldStyle(.roundedBorder).disabled(model.active || model.runtime.busy)
                    ModelStorageView(modelID: model.settings.values.modelID, engine: model.settings.values.engine,
                                     refresh: model.runtime.busy.description + (model.runtime.loadedKey ?? ""))
                    Text("Download sizes are for the pinned model files, not memory use. Custom folders must contain weights compatible with the selected engine.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        if !model.runtime.installed {
                            Button("Install local runtime", action: model.installRuntime).buttonStyle(PrimaryButton()).disabled(model.runtime.busy)
                        } else {
                            Button(model.modelReady ? "Reload model" : "Download & load model", action: model.loadModel)
                                .buttonStyle(PrimaryButton()).disabled(model.runtime.busy || model.active)
                        }
                        if model.runtime.busy {
                            ProgressView().controlSize(.small)
                            Button("Cancel", action: model.cancel).buttonStyle(.plain).font(.caption)
                        } else if model.runtime.loadedKey != nil {
                            Button("Unload", action: model.unloadModel).buttonStyle(.plain).font(.caption).disabled(model.active)
                        }
                    }.padding(.top, 3)
                    Text(model.runtime.message).font(.system(size: 11)).foregroundStyle(Palette.green).textSelection(.enabled)
                }
                Divider().padding(.vertical, 5)
                sectionLabel("02  /  TEXT POLISHING")
                Toggle("Polish with a language model", isOn: preferences.polish).toggleStyle(.switch).font(.system(size: 13, weight: .medium))
                    .disabled(!PolishingConsent.canChangeToggle(currentEnabled: model.settings.values.polish,
                                                               sessionActive: model.active, runtimeBusy: model.runtime.busy))
                if model.active && model.settings.values.polish {
                    Text("Turning polishing off cancels pending polishing and keeps local cleanup. Text already sent cannot be recalled.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Text("Optional. Use any text model served through a compatible chat-completions API. Ollama and LM Studio can run entirely on this Mac.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if model.settings.values.polish {
                    VStack(alignment: .leading, spacing: 10) {
                        labeledField("Endpoint", text: preferences.endpoint)
                        HStack(alignment: .bottom, spacing: 10) {
                            labeledField("Model name", text: preferences.textModel)
                            Button(model.isDiscovering ? "Finding…" : "Find models", action: model.discoverTextModels)
                                .padding(.bottom, 2).disabled(model.active || model.runtime.busy || model.isDiscovering)
                            if model.isDiscovering { Button("Cancel", action: model.cancelDiscovery).font(.caption) }
                        }
                        if !model.ollamaModels.isEmpty {
                            Picker("Installed models", selection: preferences.textModel) {
                                ForEach(model.ollamaModels, id: \.self) { Text($0).tag($0) }
                            }.font(.caption)
                        }
                        Text(model.settings.values.endpoint.hasPrefix("http://localhost") || model.settings.values.endpoint.hasPrefix("http://127.0.0.1")
                             ? "Only transcript text is sent to your local server."
                             : "Transcript text will be sent to the endpoint you configure. Audio stays on this Mac.")
                            .font(.system(size: 11)).foregroundStyle(Palette.green)
                    }.disabled(model.active || model.runtime.busy)
                }
            }.padding(.bottom, 10)
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    private var preferences: Binding<Preferences> { Binding(get: { model.settings.values }, set: { model.settings.values = $0 }) }
    @State private var apiKey = ""
    @State private var keyMessage = ""
    @State private var login = SMAppService.mainApp.status == .enabled
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                title("Make it feel like you.", subtitle: "A few thoughtful choices. Nothing in your way.")
                sectionLabel("WRITING")
                Picker("Writing style", selection: preferences.style) {
                    ForEach(WritingStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Text("Local cleanup fixes spacing, fillers, and spoken punctuation. Professional and casual rewriting use your optional text model.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                Picker("Speech language", selection: preferences.language) {
                    Text("Detect automatically").tag("auto")
                    ForEach(["en", "es", "fr", "de", "it", "pt", "ja", "zh", "ko", "hi"], id: \.self) {
                        Text(Locale.current.localizedString(forLanguageCode: $0) ?? $0).tag($0)
                    }
                }
                Text("Whisper uses this language hint. Parakeet detects supported languages automatically. Select English for Parakeet spoken commands such as “new paragraph” and “question mark”.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                Toggle("Interpret spoken punctuation commands in English", isOn: preferences.spokenCommands)
                Text("Off preserves literal words such as “colon”. Turn on to interpret commands such as “new paragraph” and “question mark”.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                Divider()
                sectionLabel("MAC INTEGRATION")
                Toggle("Insert text into the app I’m using", isOn: preferences.autoInsert)
                HStack {
                    Label(model.accessibility ? "Accessibility is enabled" : "Accessibility is needed for insertion", systemImage: model.accessibility ? "checkmark.circle" : "lock")
                        .font(.system(size: 12)).foregroundStyle(model.accessibility ? Palette.green : Palette.muted)
                    Spacer()
                    Button(model.accessibility ? "Check again" : "Enable insertion") {
                        if !model.accessibility { model.inserter.requestPermission() }
                        model.refreshPermissions()
                    }
                }
                Toggle("Open wisprM at login", isOn: $login).onChange(of: login) { _, value in
                    do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { model.error = error.localizedDescription; login = SMAppService.mainApp.status == .enabled }
                }
                Divider()
                sectionLabel("PRIVACY")
                Toggle("Keep the last 30 dictations on this Mac", isOn: preferences.keepHistory)
                Text("History is off by default. Turning it off deletes saved history. Temporary audio files are deleted after transcription or cancellation, and cleaned up on the next launch after a crash.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                HStack { Text("Saved history: \(model.history.count) items").font(.caption); Spacer(); Button("Delete history", action: model.clearHistory).disabled(model.history.isEmpty && !model.hasSavedHistory) }
                Divider()
                sectionLabel("OPTIONAL SERVER CREDENTIAL")
                Text("Credential for: " + (EndpointOrigin.key(for: model.settings.values.endpoint) ?? "Enter a valid server endpoint first"))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                Text("Credentials are never reused across servers. If you saved a key in an earlier version, save it again for this server.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                SecureField("API key, if your text server requires one", text: $apiKey).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save in Keychain") {
                        do { try CredentialStore.save(apiKey, for: model.settings.values.endpoint); apiKey = ""; keyMessage = "Saved securely in macOS Keychain." }
                        catch { model.error = error.localizedDescription }
                    }
                    Button("Remove key") {
                        do { try CredentialStore.save("", for: model.settings.values.endpoint); keyMessage = "Credential removed." } catch { model.error = error.localizedDescription }
                    }
                    Text(keyMessage).font(.caption).foregroundStyle(Palette.muted)
                }
                Text("No camera access, screen capture, or analytics. Speech recognition runs locally using your selected model.")
                    .font(.system(size: 11)).foregroundStyle(Palette.green).padding(.top, 8)
            }.toggleStyle(.switch).font(.system(size: 13)).padding(.bottom, 15)
        }.disabled(model.active)
            .onChange(of: model.settings.values.endpoint) { _, _ in apiKey = ""; keyMessage = "" }
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("Words worth keeping.", subtitle: "Your recent dictations, saved only when you choose.")
            if model.history.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "text.book.closed").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.green)
                    Text(model.settings.values.keepHistory ? "A clean page." : "Your history is private. And optional.").font(.system(size: 23, design: .serif))
                    Text(model.settings.values.keepHistory ? "Your next dictation will appear here." : "Enable local history in Settings to keep your last 30 dictations.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    if !model.settings.values.keepHistory { Button("Open Settings") { model.page = .settings }.buttonStyle(PrimaryButton()) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.history) { entry in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(entry.date, style: .date)
                                    Text("· \(entry.engine)")
                                    Spacer()
                                    Button { model.copy(entry.text) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).accessibilityLabel("Copy dictation")
                                }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                                Text(entry.text).font(.system(size: 15, design: .serif)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(18).background(.white.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                HStack { Spacer(); Button("Delete all history", action: model.clearHistory) }
            }
        }
    }
}

struct HUDView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 13) {
            Mark(small: true)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(model.recording ? "Listening" : model.phase == .polishing ? "Polishing" : "Transcribing")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(model.recording ? String(format: "%02d:%02d", model.seconds / 60, model.seconds % 60) : model.phase == .polishing ? "AI POLISH" : "ON DEVICE")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
                }
                if model.recording { LiveAudioMeter(levels: model.audioLevels) }
                else { ProgressView().controlSize(.mini) }
                Text("⌃ ⌥ Space to finish").font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
            Button(action: model.cancel) { Image(systemName: "xmark").font(.system(size: 11)) }
                .buttonStyle(.plain).accessibilityLabel("Cancel dictation")
        }.padding(17).frame(width: 320).foregroundStyle(Palette.ink).background(Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 15))
    }
}

private func title(_ text: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 9) {
        Text(text).font(.system(size: 31, design: .serif))
        Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
    }.padding(.bottom, 5)
}
private func sectionLabel(_ text: String) -> some View {
    Text(text).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundStyle(Palette.muted)
}
private func labeledField(_ label: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(label).font(.system(size: 11, weight: .medium))
        TextField(label, text: text).textFieldStyle(.roundedBorder)
    }
}
