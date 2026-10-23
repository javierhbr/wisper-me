import AVFoundation
import Foundation

private final class CaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0
    private var error: Error?
    func record(level: Float, error: Error?) { lock.lock(); defer { lock.unlock() }; peak = max(peak, level); if let error { self.error = error } }
    func result() -> (Float, Error?) { lock.lock(); defer { lock.unlock() }; return (peak, error) }
}

@MainActor final class AudioCapture {
    private let engine = AVAudioEngine()
    private var tapped = false
    private var path: URL?
    private var stats = CaptureState()

    func start(onLevel: @escaping @Sendable (Float) -> Void) throws {
        cancel()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AppFailure("No microphone is available. Connect an input device and try again.") }
        let url = AppPaths.recordings.appendingPathComponent(UUID().uuidString + ".caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        path = url
        let statistics = CaptureState(); stats = statistics
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            var level: Float = 0
            if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
                level = sqrt(sum / Float(buffer.frameLength))
            }
            do { try file.write(from: buffer); statistics.record(level: level, error: nil) }
            catch { statistics.record(level: level, error: error) }
            onLevel(min(1, level * 12))
        }
        tapped = true
        engine.prepare()
        do { try engine.start() } catch { cancel(); throw error }
    }

    func stop() throws -> URL {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        let (peak, error) = stats.result()
        if let error { cancel(); throw error }
        guard let path else { throw AppFailure("No active recording.") }
        guard peak > 0.001 else { cancel(); throw AppFailure("No speech was detected. Check your microphone input and try again.") }
        self.path = nil
        return path
    }

    func cancel() {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        if let path { try? FileManager.default.removeItem(at: path) }
        path = nil
    }
}
