import Foundation

public enum InferenceResourcePressure: Sendable { case normal, constrained, critical }
public enum SpeechPreloadTrigger: Sendable { case coldLaunch, dictateSelected, foregroundReturn }

/// Small, explicit decisions shared by the app and its lifecycle regression tests.
public enum InferenceEnergyPolicy {
    public static func shouldPreloadSpeech(trigger: SpeechPreloadTrigger, dictateVisible: Bool,
        pressure: InferenceResourcePressure) -> Bool {
        dictateVisible && pressure == .normal && trigger != .foregroundReturn
    }
    public static func retainSpeechForApple(foreground: Bool, pressure: InferenceResourcePressure) -> Bool {
        foreground && pressure == .normal
    }
    public static func cancelPolishing(mode: PolishMode, pressure: InferenceResourcePressure) -> Bool {
        (pressure == .critical && mode.requiresForeground) || (pressure == .constrained && mode == .local)
    }
    public static func reuseReceipt(recordedFolder: URL?, cachedFolder: URL?, loadedFolder: URL, bytes: Int64?) -> Bool {
        guard let recordedFolder, let cachedFolder, let bytes, bytes > 0 else { return false }
        let loaded = loadedFolder.resolvingSymlinksInPath().standardizedFileURL.path
        return recordedFolder.resolvingSymlinksInPath().standardizedFileURL.path == loaded
            && cachedFolder.resolvingSymlinksInPath().standardizedFileURL.path == loaded
    }
}
