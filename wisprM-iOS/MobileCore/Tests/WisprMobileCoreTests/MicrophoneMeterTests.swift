import XCTest
@testable import WisprMobileCore

final class MicrophoneMeterTests: XCTestCase {
    func testSilenceIsFlatAndSpeechProducesAVisibleTrail() {
        var meter = MicrophoneMeter()
        for _ in 0..<50 { meter.update(decibels: -80) }
        XCTAssertEqual(meter.level, 0)
        XCTAssertTrue(meter.samples.allSatisfy { $0 == 0 })
        for _ in 0..<8 { meter.update(decibels: -20) }
        XCTAssertGreaterThan(meter.level, 0.5)
        XCTAssertGreaterThan(meter.samples.last ?? 0, 0.5)
        let speaking = meter.level
        meter.update(decibels: -80)
        XCTAssertLessThan(meter.level, speaking)
        XCTAssertGreaterThan(meter.level, 0)
        for _ in 0..<80 { meter.update(decibels: -80) }
        XCTAssertLessThan(meter.level, 0.001)
    }

    func testHistoryIsBoundedAndInvalidPowerNeverBreaksTheDisplay() {
        var meter = MicrophoneMeter()
        for _ in 0..<1000 {
            for power: Float in [-160, -35, 100, .nan, .infinity] { meter.update(decibels: power) }
        }
        XCTAssertEqual(meter.samples.count, MicrophoneMeter.sampleCount)
        XCTAssertTrue(meter.samples.allSatisfy { $0.isFinite && (0...1).contains($0) })
        meter.reset()
        XCTAssertEqual(meter.level, 0)
        XCTAssertTrue(meter.samples.allSatisfy { $0 == 0 })
    }
}
