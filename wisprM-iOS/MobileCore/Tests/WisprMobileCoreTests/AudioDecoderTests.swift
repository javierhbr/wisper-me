import XCTest
import AVFoundation
@testable import WisprMobileCore

final class AudioDecoderTests: XCTestCase {
    func testResamplingStopsAtEOFWithoutDiscardingValidAudio() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let rate = 22_050.0
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050)!
        buffer.frameLength = 22_050
        for index in 0..<22_050 { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * 440 / rate)) * 0.3 }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let result = try AudioDecoder.samples(from: url)
        XCTAssertLessThanOrEqual(abs(result.count - 16_000), 32)
        XCTAssertGreaterThan(result.map { abs($0) }.max() ?? 0, 0.2)
    }
    func testStereoInputIsConvertedToMono() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for index in 0..<16_000 { buffer.floatChannelData![0][index] = 0; buffer.floatChannelData![1][index] = 0.5 }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let result = try AudioDecoder.samples(from: url)
        XCTAssertLessThanOrEqual(abs(result.count - 16_000), 32)
        XCTAssertGreaterThan(result.max() ?? 0, 0.1)
    }
    func testOversizedAudioIsRejectedBeforeOpening() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: 100 * 1024 * 1024 + 1); try file.close()
        XCTAssertThrowsError(try AudioDecoder.samples(from: url))
    }
}
