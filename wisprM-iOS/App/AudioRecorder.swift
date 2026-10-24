import AVFoundation
import Combine
import WisprMobileCore

@MainActor final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var level: Float = 0
    @Published private(set) var seconds: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var interruption: NSObjectProtocol?
    var onFinish: ((URL) -> Void)?
    var onError: ((Error) -> Void)?

    func start(in directory: URL) async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw MobileFailure.message("Microphone access is off. Enable it for wisprM in iPhone Settings.")
        }
        try Task.checkCancellation()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        var attempted: AVAudioRecorder?
        var attemptedURL: URL?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
            attemptedURL = url
            let value = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            attempted = value
            value.delegate = self; value.isMeteringEnabled = true
            guard value.prepareToRecord(), value.record(forDuration: 180) else {
                throw MobileFailure.message("The microphone could not start recording.")
            }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            recorder = value; seconds = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let recorder = self.recorder else { return }
                    recorder.updateMeters(); self.seconds = recorder.currentTime
                    self.level = max(0, min(1, pow(10, recorder.averagePower(forChannel: 0) / 25)))
                }
            }
            interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                object: session, queue: .main) { [weak self] note in
                    guard (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue else { return }
                    Task { @MainActor in self?.finish() }
                }
        } catch {
            attempted?.delegate = nil; attempted?.stop()
            if let attemptedURL { try? FileManager.default.removeItem(at: attemptedURL) }
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }
    func finish() {
        guard let recorder else { return }
        let url = recorder.url
        let duration = max(seconds, recorder.currentTime)
        self.recorder = nil; recorder.delegate = nil; recorder.stop(); cleanSession()
        if duration >= 0.25 { onFinish?(url) }
        else { try? FileManager.default.removeItem(at: url); onError?(MobileFailure.message("Speak a little longer before finishing.")) }
    }
    func cancel() {
        guard let recorder else { cleanSession(); return }
        self.recorder = nil; recorder.delegate = nil; recorder.stop()
        try? FileManager.default.removeItem(at: recorder.url); cleanSession()
    }
    private func cleanSession() {
        timer?.invalidate(); timer = nil; level = 0
        if let interruption { NotificationCenter.default.removeObserver(interruption) }; interruption = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.recorder = nil; self.cleanSession()
            if flag { self.onFinish?(recorder.url) }
            else { try? FileManager.default.removeItem(at: recorder.url); self.onError?(MobileFailure.message("Recording was interrupted before audio could be saved.")) }
        }
    }
}
