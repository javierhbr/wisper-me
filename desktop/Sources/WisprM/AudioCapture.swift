import AVFoundation
import Foundation

/// Shared only between the audio tap and the UI's low-frequency meter poll.
final class CaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private let frameLimit: AVAudioFramePosition
    private let startedAt: TimeInterval
    private let durationLimit: TimeInterval
    private var frames: AVAudioFramePosition = 0
    private var peak: Float = 0
    private var currentLevel: Float = 0
    private var error: Error?

    init(sampleRate: Double = 48_000, durationLimit: TimeInterval = 180,
         startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.frameLimit = AVAudioFramePosition((sampleRate * durationLimit).rounded(.down))
        self.startedAt = startedAt
        self.durationLimit = durationLimit
    }

    var elapsedTime: TimeInterval { max(0, ProcessInfo.processInfo.systemUptime - startedAt) }

    func reserveFrames(_ requested: AVAudioFrameCount) -> AVAudioFrameCount {
        lock.lock(); defer { lock.unlock() }
        guard error == nil, elapsedTime < durationLimit else { return 0 }
        let allowed = min(AVAudioFramePosition(requested), max(0, frameLimit - frames))
        frames += allowed
        return AVAudioFrameCount(allowed)
    }

    func record(level: Float, error: Error? = nil) {
        lock.lock(); defer { lock.unlock() }
        peak = max(peak, level)
        currentLevel = min(1, level * 12)
        if let error { self.error = error }
    }

    var meter: Float {
        lock.lock(); defer { lock.unlock() }
        return currentLevel
    }

    var shouldFinish: Bool {
        lock.lock(); defer { lock.unlock() }
        return frames >= frameLimit || error != nil || elapsedTime >= durationLimit
    }

    func result() -> (peak: Float, error: Error?) {
        lock.lock(); defer { lock.unlock() }
        return (peak, error)
    }
}

enum AudioBufferAnalysis {
    /// The strongest channel determines eligibility: a quiet channel zero must not hide speech elsewhere.
    static func rootMeanSquare(_ buffer: AVAudioPCMBuffer, frameCount: AVAudioFrameCount? = nil) -> Float {
        let frames = Int(min(frameCount ?? buffer.frameLength, buffer.frameLength))
        guard frames > 0 else { return 0 }
        let channels = Int(buffer.format.channelCount)
        let stride = buffer.stride
        var strongest: Double = 0
        if let samples = buffer.floatChannelData {
            for channel in 0..<channels {
                var sum: Double = 0
                for frame in 0..<frames {
                    let value = Double(samples[channel][frame * stride])
                    if value.isFinite { sum += value * value }
                }
                strongest = max(strongest, sqrt(sum / Double(frames)))
            }
        } else if let samples = buffer.int16ChannelData {
            for channel in 0..<channels {
                var sum: Double = 0
                for frame in 0..<frames {
                    let value = Double(samples[channel][frame * stride]) / 32768
                    sum += value * value
                }
                strongest = max(strongest, sqrt(sum / Double(frames)))
            }
        } else if let samples = buffer.int32ChannelData {
            for channel in 0..<channels {
                var sum: Double = 0
                for frame in 0..<frames {
                    let value = Double(samples[channel][frame * stride]) / 2_147_483_648
                    sum += value * value
                }
                strongest = max(strongest, sqrt(sum / Double(frames)))
            }
        }
        return Float(strongest)
    }

    static func prefix(_ buffer: AVAudioPCMBuffer, frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard frames > 0, frames <= buffer.frameLength,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: frames) else { return nil }
        copy.frameLength = frames
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        for index in 0..<min(source.count, destination.count) {
            guard let from = source[index].mData, let to = destination[index].mData else { return nil }
            let bytes = min(Int(frames) * bytesPerFrame, Int(source[index].mDataByteSize), Int(destination[index].mDataByteSize))
            memcpy(to, from, bytes)
        }
        return copy
    }
}

@MainActor final class AudioCapture {
    private let engine = AVAudioEngine()
    private var tapped = false
    private var path: URL?
    private var stats = CaptureState()

    var meter: Float { stats.meter }
    var elapsedTime: TimeInterval { stats.elapsedTime }
    var shouldFinish: Bool { stats.shouldFinish }
    var recordingURL: URL? { path }

    func start() throws {
        cancel()
        guard path == nil else { throw AppFailure("The previous temporary recording could not be removed. Try cleanup before recording again.") }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AppFailure("No microphone is available. Connect an input device and try again.")
        }
        guard [.pcmFormatFloat32, .pcmFormatInt16, .pcmFormatInt32].contains(format.commonFormat) else {
            throw AppFailure("This microphone's sample format is unsupported. Choose a standard PCM input format.")
        }
        let url = AppPaths.recordings.appendingPathComponent(UUID().uuidString + ".caf")
        path = url
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let statistics = CaptureState(sampleRate: format.sampleRate)
            stats = statistics
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                let allowed = statistics.reserveFrames(buffer.frameLength)
                guard allowed > 0 else { return }
                let level = AudioBufferAnalysis.rootMeanSquare(buffer, frameCount: allowed)
                do {
                    if allowed == buffer.frameLength { try file.write(from: buffer) }
                    else if let clipped = AudioBufferAnalysis.prefix(buffer, frames: allowed) {
                        try file.write(from: clipped)
                    } else { throw AppFailure("Could not finish the bounded audio recording.") }
                    statistics.record(level: level)
                } catch { statistics.record(level: level, error: error) }
            }
            tapped = true
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }
    }

    func stop() throws -> URL {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        let (peak, error) = stats.result()
        if let error { cancel(); throw error }
        guard let path else { throw AppFailure("No active recording.") }
        guard peak > 0.001 else {
            cancel()
            throw AppFailure("No speech was detected. Check your microphone input and try again.")
        }
        self.path = nil
        return path
    }

    func cancel() {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        if let path {
            do { try FileManager.default.removeItem(at: path); self.path = nil }
            catch {
                let failure = error as NSError
                if failure.domain == NSCocoaErrorDomain && failure.code == NSFileNoSuchFileError { self.path = nil }
                // Retain ownership on other errors so the caller can retry and report cleanup.
            }
        }
    }
}
