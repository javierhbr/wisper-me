import Foundation
import AVFoundation

public enum AudioDecoder {
    /// Bounded conversion to the mono 16 kHz Float32 contract of both recognizers.
    public static func samples(from url: URL) throws -> [Float] {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100 * 1024 * 1024 else { throw MobileFailure.message("Audio imports are limited to 100 MB.") }
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard source.sampleRate > 0, Double(file.length) / source.sampleRate <= 600 else {
            throw MobileFailure.message("Audio imports are limited to ten minutes.")
        }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 8192),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 8192) else {
            throw MobileFailure.message("This audio format cannot be converted on this device.")
        }
        var result: [Float] = []
        converter.downmix = true
        result.reserveCapacity(min(9_600_000, Int(Double(file.length) * 16_000 / source.sampleRate)))
        var finished = false
        while !finished {
            try Task.checkCancellation()
            var conversionError: NSError?
            var readError: Error?
            let status = converter.convert(to: output, error: &conversionError) { requested, inputStatus in
                do {
                    let remaining = file.length - file.framePosition
                    guard remaining > 0 else { inputStatus.pointee = .endOfStream; return nil }
                    let frames = min(requested, input.frameCapacity, AVAudioFrameCount(min(remaining, Int64(UInt32.max))))
                    try file.read(into: input, frameCount: frames)
                    inputStatus.pointee = input.frameLength == 0 ? .endOfStream : .haveData
                    return input.frameLength == 0 ? nil : input
                } catch { readError = error; inputStatus.pointee = .endOfStream; return nil }
            }
            if let readError { throw readError }
            if let conversionError { throw conversionError }
            if let data = output.floatChannelData?[0], output.frameLength > 0 {
                result.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
            }
            guard result.count <= 9_600_000 else { throw MobileFailure.message("The decoded audio exceeds ten minutes.") }
            switch status {
            case .endOfStream: finished = true
            case .error: throw MobileFailure.message("Audio conversion failed.")
            case .inputRanDry where output.frameLength == 0: finished = true
            default: break
            }
        }
        guard !result.isEmpty else { throw MobileFailure.message("The audio file contains no samples.") }
        return result
    }
}
