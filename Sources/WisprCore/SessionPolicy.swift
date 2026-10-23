import Foundation

/// A capture cannot acquire new consent or change destinations after it starts.
public enum PolishingConsent {
    public static func canChangeToggle(currentEnabled: Bool, sessionActive: Bool, runtimeBusy: Bool) -> Bool {
        currentEnabled || (!sessionActive && !runtimeBusy)
    }
    public static func allows(capturedEnabled: Bool, liveEnabled: Bool,
                              capturedEndpoint: String, liveEndpoint: String) -> Bool {
        capturedEnabled && liveEnabled
            && EndpointPolicy.validate(capturedEndpoint)?.absoluteString == EndpointPolicy.validate(liveEndpoint)?.absoluteString
            && EndpointPolicy.validate(capturedEndpoint) != nil
    }
}

public enum InsertionEligibility {
    public static func allows(role: String?, subrole: String?) -> Bool {
        guard let role, let subrole,
              ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) else { return false }
        return subrole != "AXSecureTextField"
    }
}

public enum AudioImportPolicy {
    public static let maximumBytes: Int64 = 100 * 1024 * 1024
    public static let extensions = ["wav", "caf", "aiff", "aif", "aifc", "m4a", "mp4",
                                    "mp3", "flac", "ogg", "opus", "webm", "weba", "aac"]
    public static func accepts(fileExtension: String, bytes: Int64) -> Bool {
        bytes >= 0 && bytes <= maximumBytes && extensions.contains(fileExtension.lowercased())
    }
}
