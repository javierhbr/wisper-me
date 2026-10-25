import Foundation

/// A bounded history of real microphone power, with a noise floor and fast attack.
public struct MicrophoneMeter: Sendable {
    public static let sampleCount = 36
    public private(set) var samples = Array(repeating: Float(0), count: sampleCount)
    public private(set) var level: Float = 0
    public init() {}

    public mutating func update(decibels: Float) {
        let power = decibels.isFinite ? min(0, max(-80, decibels)) : -80
        let target: Float = power <= -50 ? 0 : pow((power + 50) / 50, 0.7)
        level += (target - level) * (target > level ? 0.65 : 0.25)
        if level < 0.0001 { level = 0 }
        samples.removeFirst()
        samples.append(level)
    }

    public mutating func reset() {
        level = 0
        samples = Array(repeating: 0, count: Self.sampleCount)
    }
}
