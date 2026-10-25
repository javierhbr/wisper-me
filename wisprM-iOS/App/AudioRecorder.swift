import AVFoundation
import Combine
import UIKit
import WisprMobileCore

@MainActor final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var meter = MicrophoneMeter()
    var level: Float { meter.level }
    @Published private(set) var seconds: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var warningPlayer: AVAudioPlayer?
    private var idleTimerWasDisabled: Bool?
    private var timer: Timer?
    private var meteringVisible = true
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
            guard let alert = NSDataAsset(name: "RecordingWarning") else {
                throw MobileFailure.message("The recording warning sound is missing.")
            }
            let warning = try AVAudioPlayer(data: alert.data)
            guard warning.prepareToPlay() else {
                throw MobileFailure.message("The recording warning sound could not be prepared.")
            }
            let value = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            attempted = value
            value.delegate = self; value.isMeteringEnabled = meteringVisible
            guard value.prepareToRecord(), value.record(forDuration: RecordingLimits.maximumDuration) else {
                throw MobileFailure.message("The microphone could not start recording.")
            }
            holdScreenAwake()
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            // Schedule on the audio device clock so hiding metering does not disable the alert.
            warningPlayer = warning
            guard warning.play(atTime: warning.deviceCurrentTime + RecordingLimits.warningTime) else {
                throw MobileFailure.message("The recording warning sound could not be scheduled.")
            }
            recorder = value; seconds = 0; meter.reset()
            startMeteringIfNeeded()
            interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                object: session, queue: .main) { [weak self] note in
                    guard (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue else { return }
                    Task { @MainActor in self?.finish() }
                }
        } catch {
            warningPlayer?.stop(); warningPlayer = nil
            restoreScreenAutoLock()
            attempted?.delegate = nil; attempted?.stop()
            if let attemptedURL { try? FileManager.default.removeItem(at: attemptedURL) }
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }
    func setMeteringVisible(_ visible: Bool) {
        meteringVisible = visible
        recorder?.isMeteringEnabled = visible
        if visible { startMeteringIfNeeded() }
        else { timer?.invalidate(); timer = nil; meter.reset() }
    }
    private func startMeteringIfNeeded() {
        guard meteringVisible, timer == nil, recorder != nil else { return }
        sampleMeter()
        let meterTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleMeter() }
        }
        meterTimer.tolerance = 0.01
        timer = meterTimer
        RunLoop.main.add(meterTimer, forMode: .common)
    }
    private func sampleMeter() {
        guard meteringVisible, let recorder else { return }
        recorder.updateMeters()
        let elapsed = recorder.currentTime
        if Int(elapsed) != Int(seconds) { seconds = elapsed }
        var next = meter
        next.update(decibels: recorder.averagePower(forChannel: 0))
        if next.samples != meter.samples { meter = next }
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
    private func holdScreenAwake() {
        if idleTimerWasDisabled == nil {
            idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }
    private func restoreScreenAutoLock() {
        guard let previous = idleTimerWasDisabled else { return }
        idleTimerWasDisabled = nil
        UIApplication.shared.isIdleTimerDisabled = previous
    }

    #if DEBUG
    /// Exercise the actual UIKit override without accessing the microphone.
    func verifyRecordingScreenAwakePolicy() -> Bool {
        guard recorder == nil, idleTimerWasDisabled == nil else { return false }
        let initial = UIApplication.shared.isIdleTimerDisabled
        defer {
            restoreScreenAutoLock()
            UIApplication.shared.isIdleTimerDisabled = initial
        }
        for previous in [false, true] {
            UIApplication.shared.isIdleTimerDisabled = previous
            holdScreenAwake()
            holdScreenAwake()
            guard UIApplication.shared.isIdleTimerDisabled else { return false }
            restoreScreenAutoLock()
            guard UIApplication.shared.isIdleTimerDisabled == previous else { return false }
            restoreScreenAutoLock()
            guard UIApplication.shared.isIdleTimerDisabled == previous else { return false }
        }
        return true
    }
    #endif

    private func cleanSession() {
        warningPlayer?.stop(); warningPlayer = nil
        restoreScreenAutoLock()
        timer?.invalidate(); timer = nil; meter.reset()
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
