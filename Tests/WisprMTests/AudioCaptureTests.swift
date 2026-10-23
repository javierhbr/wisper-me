import AVFoundation
import XCTest
@testable import WisprM

final class AudioCaptureTests: XCTestCase {
    func testSpeechOnSecondChannelCountsForEligibility() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)!
        buffer.frameLength = 64
        for frame in 0..<64 {
            buffer.floatChannelData![0][frame] = 0
            buffer.floatChannelData![1][frame] = 0.2
        }
        XCTAssertEqual(AudioBufferAnalysis.rootMeanSquare(buffer), 0.2, accuracy: 0.0001)
    }

    func testInterleavedSpeechOnSecondChannelUsesStride() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 2, interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32)!
        buffer.frameLength = 32
        for frame in 0..<32 {
            buffer.int16ChannelData![0][frame * buffer.stride] = 0
            buffer.int16ChannelData![1][frame * buffer.stride] = 8192
        }
        XCTAssertEqual(AudioBufferAnalysis.rootMeanSquare(buffer), 0.25, accuracy: 0.0001)
    }

    func testFrameBudgetCapsTheLastBuffer() {
        let state = CaptureState(sampleRate: 10, durationLimit: 1)
        XCTAssertEqual(state.reserveFrames(8), 8)
        XCTAssertEqual(state.reserveFrames(8), 2)
        XCTAssertEqual(state.reserveFrames(8), 0)
        XCTAssertTrue(state.shouldFinish)
    }

    func testMonotonicDeadlineExpiresEvenWithoutAudioCallbacks() {
        let state = CaptureState(sampleRate: 10, durationLimit: 1,
                                 startedAt: ProcessInfo.processInfo.systemUptime - 2)
        XCTAssertEqual(state.reserveFrames(8), 0)
        XCTAssertTrue(state.shouldFinish)
    }

    func testPrefixCopiesOnlyPermittedFrames() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8)!
        buffer.frameLength = 8
        for frame in 0..<8 {
            buffer.floatChannelData![0][frame] = Float(frame)
            buffer.floatChannelData![1][frame] = Float(frame + 10)
        }
        let prefix = try XCTUnwrap(AudioBufferAnalysis.prefix(buffer, frames: 3))
        XCTAssertEqual(prefix.frameLength, 3)
        XCTAssertEqual(prefix.floatChannelData![0][2], 2)
        XCTAssertEqual(prefix.floatChannelData![1][2], 12)
        XCTAssertEqual(buffer.frameLength, 8, "The borrowed input buffer must remain unchanged")
    }
}
