import SwiftUI
import AppIntents

@main struct WisprMobileApp: App {
    @StateObject private var model = MobileModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            MobileRootView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.copyWhenActive(); model.refreshAppleIntelligenceAvailability() } else { model.suspendLocalPolishing() }
                }
                .onOpenURL { url in if url.scheme == "wisprm" { model.tab = 0 } }
                .onReceive(NotificationCenter.default.publisher(for: .init("com.wisprm.mobile.openDictation"))) { _ in model.tab = 0 }
                .task {
                    #if DEBUG
                    await model.runIntegrationIfRequested()
                    #endif
                }
        }
    }
}

struct OpenDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "Open wisprM Dictation"
    static var description = IntentDescription("Open wisprM to record and transcribe speech privately on your iPhone.")
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: .init("com.wisprm.mobile.openDictation"), object: nil) }
        return .result()
    }
}

struct WisprShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenDictationIntent(), phrases: ["Dictate with \(.applicationName)"],
                    shortTitle: "Dictate", systemImageName: "waveform")
    }
}
