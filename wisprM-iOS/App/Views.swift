import SwiftUI
import UniformTypeIdentifiers
import WisprCore
import WisprMobileCore

enum MobileTheme {
    static let green = Color(red: 0.14, green: 0.34, blue: 0.25)
    static let paper = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.08, green: 0.11, blue: 0.09, alpha: 1) : UIColor(red: 0.967, green: 0.959, blue: 0.933, alpha: 1)
    })
}

struct MobileRootView: View {
    @ObservedObject var model: MobileModel
    var body: some View {
        TabView(selection: $model.tab) {
            NavigationStack { DictationView(model: model) }.tabItem { Label("Dictate", systemImage: "waveform") }.tag(0)
            NavigationStack { MobileModelsView(model: model) }.tabItem { Label("Models", systemImage: "square.stack.3d.up") }.tag(1)
            NavigationStack { MobileHistoryView(model: model) }.tabItem { Label("History", systemImage: "clock") }.tag(2)
            NavigationStack { MobileSettingsView(model: model) }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(3)
        }.tint(MobileTheme.green)
        .alert("wisprM", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

struct DictationView: View {
    @ObservedObject var model: MobileModel
    @State private var importing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Image(systemName: "waveform").font(.title); Text("wisprM").font(.title2.bold()); Spacer(); Label("ON DEVICE", systemImage: "circle.fill").font(.system(size: 9, weight: .semibold, design: .monospaced)) }.foregroundStyle(MobileTheme.green)
                Text("A thought.\nBeautifully put.").font(.system(size: 38, weight: .regular, design: .serif))
                Text("Record up to 10 minutes. A sound at 9:30 gives you 30 seconds to finish.").foregroundStyle(.secondary)
                HStack { Text(model.preferences.speechChoice.name).font(.caption.weight(.medium)); Spacer(); Text(model.preferences.style.rawValue).font(.caption).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.phase == .recording ? "LISTENING" : "YOUR WORDS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    TextEditor(text: $model.transcript).frame(minHeight: 180).scrollContentBackground(.hidden)
                        .accessibilityLabel("Dictated text").disabled(model.busy)
                    HStack {
                        Text("\(model.transcript.split(whereSeparator: \.isWhitespace).count) words").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { model.copy() } label: { Label("Copy", systemImage: "doc.on.doc") }.disabled(model.transcript.isEmpty)
                        ShareLink(item: model.transcript) { Image(systemName: "square.and.arrow.up") }.disabled(model.transcript.isEmpty)
                    }
                }.padding(18).background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
                RecordingControl(model: model, recorder: model.recorder)
                Text(model.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                if !model.canDictate && !model.busy {
                    Button("Choose and load a model") { model.tab = 1 }.buttonStyle(.bordered)
                }
                Button { importing = true } label: { Label("Transcribe an audio file", systemImage: "waveform.badge.plus") }
                    .disabled(model.busy || !model.ready)
                Text("Completed text is copied automatically while wisprM is open. Return to the app to copy a result completed in the background, or insert it with the wisprM keyboard.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.background(MobileTheme.paper).toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie]) { result in
            do { model.importAudio(try result.get()) } catch { model.error = error.localizedDescription }
        }
    }
}

struct RecordingControl: View {
    @ObservedObject var model: MobileModel
    @ObservedObject var recorder: AudioRecorder
    var body: some View {
        VStack(spacing: 14) {
            if model.phase == .recording {
                LiveMicrophoneView(meter: recorder.meter, seconds: recorder.seconds)
            }
            if model.phase == .recording || !model.busy {
                Button {
                    if model.phase == .recording { model.finish() }
                    else if !model.canDictate { model.tab = 1 }
                    else { model.start() }
                } label: {
                    Label(model.phase == .recording ? "Finish dictation" : model.canDictate ? "Start dictation" : "Choose a speech model",
                          systemImage: model.phase == .recording ? "stop.fill" : model.canDictate ? "mic.fill" : "square.stack.3d.up")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                }.buttonStyle(.borderedProminent)
            } else {
                HStack { ProgressView(); Text(model.phase.rawValue.capitalized); Spacer() }.padding()
            }
            if model.busy { Button("Cancel", role: .cancel, action: model.cancel).disabled(model.phase == .cancelling) }
        }
    }
}

struct LiveMicrophoneView: View {
    let meter: MicrophoneMeter
    let seconds: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private var ink: Color { colorScheme == .dark ? Color(red: 0.49, green: 0.79, blue: 0.64) : MobileTheme.green }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 3) {
                ForEach(Array([0.45, 0.8, 1.0, 0.7, 0.35].enumerated()), id: \.offset) { _, scale in
                    Capsule().fill(ink)
                        .frame(width: 4, height: 4 + CGFloat(meter.level) * 30 * scale)
                }
            }
            .frame(width: 32, height: 36)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Listening").font(.headline)
                    Spacer()
                    Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    let width = max(2, (geometry.size.width - CGFloat(meter.samples.count - 1) * 3) / CGFloat(meter.samples.count))
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(meter.samples.indices, id: \.self) { index in
                            Capsule().fill(ink.opacity(0.22 + Double(meter.samples[index]) * 0.78))
                                .frame(width: width, height: 4 + CGFloat(meter.samples[index]) * 24)
                        }
                    }
                    .frame(height: geometry.size.height)
                }
                .frame(height: 28)
            }
        }
        .padding(16)
        .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: meter.samples)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone input")
        .accessibilityValue("\(meter.level > 0.1 ? "Sound detected" : "Listening for sound"), \(Int(seconds)) seconds recorded")
    }
}

struct MobileModelsView: View {
    @ObservedObject var model: MobileModel
    @State private var deleting: SpeechChoice?
    @State private var deletingAll = false
    @State private var importingFolder = false
    @State private var importingText = false
    @State private var customRepository = ""
    @State private var customVariant = ""
    private var choices: [SpeechChoice] { SpeechChoice.presets + (model.preferences.customSpeechChoice.map { [$0] } ?? []) }
    var body: some View {
        List {
            Section {
                Text("Choose what listens.").font(.system(size: 28, design: .serif))
                Text("Both speech engines run locally. Download a model once, then transcribe offline.").font(.callout).foregroundStyle(.secondary)
            }.listRowBackground(Color.clear)
            Section("Speech recognition") {
                ForEach(choices) { choice in
                    let selected = model.preferences.modelID == choice.id
                    Button { model.preferences.modelID = choice.id } label: {
                        HStack(spacing: 14) {
                            Image(systemName: choice.engine == .whisper ? "wind" : "bird").font(.title2).frame(width: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(choice.name).font(.headline)
                                if let receipt = model.receipts[choice.id] {
                                    Text(ByteCountFormatter.string(fromByteCount: receipt.bytes, countStyle: .file) + " stored on iPhone").font(.caption)
                                } else if let bytes = choice.estimatedDownloadBytes {
                                    Text("≈ " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " download").font(.caption)
                                }
                            }
                            Spacer()
                            if selected { Image(systemName: "checkmark.circle.fill") }
                        }.padding(.vertical, 7).foregroundStyle(selected ? Color.white : Color.primary)
                    }.disabled(model.busy).listRowBackground(selected ? MobileTheme.green : Color(uiColor: .secondarySystemGroupedBackground))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Section("Compatible custom speech models") {
                TextField("WhisperKit owner/repository", text: $customRepository).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Variant folder name", text: $customVariant).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Use custom Whisper repository") { model.addWhisperRepository(customRepository, variant: customVariant) }
                Button("Import speech model folder from Files") { importingText = false; importingFolder = true }
                Text("For folder imports, select Whisper or Parakeet first. Use a complete WhisperKit Core ML folder or Parakeet v3 compiled components and vocabulary. Mac MLX speech weights are not compatible.").font(.footnote).foregroundStyle(.secondary)
            }.disabled(model.busy)
            Section {
                Text(model.preferences.speechChoice.repository).font(.caption.monospaced()).textSelection(.enabled)
                if let receipt = model.receipts[model.preferences.modelID], let path = receipt.folder {
                    Text(path.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Delete downloaded model", role: .destructive) { deleting = model.preferences.speechChoice }.disabled(model.busy)
                }
                Button(model.ready ? "Reload speech model" : model.cachedSpeechFolder != nil ? "Load cached speech model" : "Download & load speech model", action: model.loadSpeech).disabled(model.busy)
                if model.loadedID != nil || model.textModelID != nil { Button("Unload models", action: model.unload).disabled(model.busy) }
                if model.busy {
                    ProgressView(value: model.progress)
                    Button("Cancel", action: model.cancel).disabled(model.phase == .cancelling)
                }
                Text(model.message).font(.footnote).foregroundStyle(.secondary)
                Button("Delete all downloaded model files", role: .destructive) { deletingAll = true }.disabled(model.busy)
            } footer: { Text("iPhone Core ML files differ from the Mac MLX downloads. Storage size is measured after installation. The operating system may compile additional caches.") }
            Section("Optional text polishing") {
                Picker("Polishing", selection: $model.preferences.polishMode) { ForEach(PolishMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .disabled(model.busy && model.preferences.polishMode == .off)
                if model.preferences.polishMode == .appleIntelligence {
                    Label(model.appleIntelligenceStatus.message,
                          systemImage: model.appleIntelligenceStatus.isAvailable ? "checkmark.circle" : "info.circle")
                        .font(.callout).foregroundStyle(model.appleIntelligenceStatus.isAvailable ? MobileTheme.green : .secondary)
                    Text("Uses Apple's on-device model with no separate model download in wisprM. Keep the app open while polishing. If it is unavailable, your locally cleaned transcript is kept.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Check availability", action: model.refreshAppleIntelligenceAvailability)
                } else if model.preferences.polishMode == .local {
                    #if targetEnvironment(simulator)
                    Text("On-device MLX polishing requires a physical iPhone. Simulator supports speech recognition and deterministic formatting; its Metal heaps are incompatible with MLX.").font(.footnote).foregroundStyle(.orange)
                    #endif
                    if model.preferences.localTextFolder == nil {
                        TextField("MLX model ID", text: $model.preferences.localTextModel).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.busy)
                    } else {
                        Text(model.preferences.localTextModel).font(.caption)
                        Button("Use a model ID instead") { model.preferences.localTextFolder = nil; model.preferences.localTextModel = "mlx-community/Qwen2.5-0.5B-Instruct-4bit" }.disabled(model.busy)
                    }
                    Button("Import MLX text model folder from Files") { importingText = true; importingFolder = true }.disabled(model.busy)
                    Button("Download text model", action: model.loadTextModel).disabled(model.busy)
                    Text("Compatible MLX language models only. A small 4-bit model is recommended. Speech weights are unloaded before polishing to reduce memory use.").font(.footnote).foregroundStyle(.secondary)
                } else if model.preferences.polishMode == .server {
                    Text("Configure an HTTPS chat-completions server in Settings. Transcript text will leave this iPhone; audio remains local.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.scrollContentBackground(.hidden).background(MobileTheme.paper).navigationTitle("Models")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(model.ready ? "Reload" : "Load", action: model.loadSpeech).disabled(model.busy)
                        .accessibilityLabel("Load selected speech model")
                }
            }
            .confirmationDialog("Delete \(deleting?.name ?? "model") from this iPhone?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete model", role: .destructive) { if let deleting { model.deleteModel(deleting) }; deleting = nil }
            } message: { Text("You can download it again. Your transcripts will remain.") }
            .confirmationDialog("Delete all model files, including partial downloads?", isPresented: $deletingAll) {
                Button("Delete model files", role: .destructive, action: model.deleteAllModels)
            }
            .fileImporter(isPresented: $importingFolder, allowedContentTypes: [.folder]) { result in
                do { model.importModelFolder(try result.get(), forText: importingText) } catch { model.error = error.localizedDescription }
            }
    }
}

struct MobileHistoryView: View {
    @ObservedObject var model: MobileModel
    @State private var confirming = false
    var body: some View {
        List {
            if model.history.isEmpty {
                ContentUnavailableView(model.preferences.historyEnabled ? "A clean page." : "History is private. And optional.",
                    systemImage: "clock", description: Text("Enable local history in Settings to keep your last 30 dictations."))
            }
            ForEach(model.history) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.date, style: .date).font(.caption).foregroundStyle(.secondary)
                    Text(item.text).textSelection(.enabled)
                    HStack {
                        Text(item.model).font(.caption).foregroundStyle(.secondary); Spacer()
                        Button("Use text") { model.transcript = item.text; model.tab = 0 }
                        ShareLink(item: item.text) { Image(systemName: "square.and.arrow.up") }
                    }
                }.padding(.vertical, 8)
            }
        }.navigationTitle("History").scrollContentBackground(.hidden).background(MobileTheme.paper)
            .toolbar { Button("Clear", role: .destructive) { confirming = true }.disabled(model.history.isEmpty) }
            .confirmationDialog("Delete saved history?", isPresented: $confirming) { Button("Delete history", role: .destructive, action: model.clearHistory) }
    }
}

struct MobileSettingsView: View {
    @ObservedObject var model: MobileModel
    @State private var key = ""
    @State private var keyMessage = ""
    var body: some View {
        Form {
            Section("Writing") {
                Picker("Style", selection: $model.preferences.style) { ForEach(WritingStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Language", selection: $model.preferences.language) {
                    Text("Automatic").tag("auto")
                    ForEach(["en", "es", "fr", "de", "it", "pt", "ja", "zh", "ko"], id: \.self) { Text(Locale.current.localizedString(forLanguageCode: $0) ?? $0).tag($0) }
                }
                Toggle("English spoken punctuation commands", isOn: $model.preferences.spokenCommands)
                Text("Choose English for commands such as ‘new paragraph’. Parakeet detects languages automatically.").font(.footnote).foregroundStyle(.secondary)
            }.disabled(model.busy)
            Section("Privacy") {
                Toggle("Keep local history", isOn: $model.preferences.historyEnabled)
                Text("History is off by default and saved history is marked excluded from device backups. Turning it off deletes history in this app; earlier backups are not changed.").font(.footnote).foregroundStyle(.secondary)
                Text("Clipboard copies do not use Universal Clipboard and expire after 10 minutes. Paste them into another app on this iPhone before they expire.").font(.footnote).foregroundStyle(.secondary)
                Text("Temporary audio is removed after processing or cancellation.").font(.footnote).foregroundStyle(.secondary)
                Button("Clear shared keyboard transcript", action: model.clearSharedText)
            }
            Section("wisprM keyboard") {
                Text("Add wisprM in Settings → General → Keyboard → Keyboards → Add New Keyboard. Record in the main app, return to another app, select wisprM with the globe key, then tap Insert latest transcript.")
                Text("The keyboard cannot access the microphone. Shared transcripts expire after ten minutes and are inserted only when you tap. Some apps and secure fields use the system keyboard.").font(.footnote).foregroundStyle(.secondary)
                if MobilePaths.group == nil { Text("Keyboard sharing is unavailable in this build. Enable the same App Group for both targets when signing in Xcode.").font(.footnote).foregroundStyle(.orange) }
                Button("Open iPhone app settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Section("Optional model server") {
                TextField("https://server.example/v1/chat/completions", text: $model.preferences.serverEndpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Model name", text: $model.preferences.serverModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Server API key", text: $key)
                Button("Save key in Keychain") {
                    do { try MobileCredentialStore.save(key, endpoint: model.preferences.serverEndpoint); key = ""; keyMessage = "Credential saved for this server." }
                    catch { model.error = error.localizedDescription }
                }
                if !keyMessage.isEmpty { Text(keyMessage).font(.caption) }
                Text("Only used when Model server polishing is selected. Audio stays local. HTTPS is required for servers outside this iPhone; localhost refers to the phone, not your Mac.").font(.footnote).foregroundStyle(.secondary)
            }.disabled(model.busy)
            Section { Text("wisprM · iPhone edition\nOriginal code and branding. No account required.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Settings").scrollContentBackground(.hidden).background(MobileTheme.paper)
    }
}
