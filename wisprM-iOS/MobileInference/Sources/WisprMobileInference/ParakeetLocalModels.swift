import Foundation
import CoreML
import FluidAudio
import WisprMobileCore

/// Cache-only adapter for TDT 0.6B v3 int8. Uses public asynchronous Core ML
/// loading without the SDK's network/repair path or global offline switches.
enum ParakeetLocalModels {
    static func load(from folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> AsrModels {
        guard AsrModels.modelsExist(at: folder, version: .v3, encoderPrecision: .int8) else {
            throw MobileFailure.message("The cached Parakeet model is incomplete. Check it in Models.")
        }
        let names = ModelNames.ASR.self
        let vocabularyURL = folder.appendingPathComponent(names.vocabularyFile)
        let size = try vocabularyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 8_000_000 else { throw MobileFailure.message("The Parakeet vocabulary has an invalid size.") }
        let entries = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: vocabularyURL))
        var vocabulary: [Int: String] = [:]
        for (key, value) in entries {
            guard let id = Int(key), id >= 0, String(id) == key else {
                throw MobileFailure.message("The Parakeet vocabulary contains an invalid token.")
            }
            vocabulary[id] = value
        }
        guard (0..<AsrModelVersion.v3.blankId).allSatisfy({ vocabulary[$0] != nil }) else {
            throw MobileFailure.message("The Parakeet vocabulary is incomplete.")
        }
        let configuration = AsrModels.defaultConfiguration()
        func component(_ name: String, units: MLComputeUnits) async throws -> MLModel {
            try Task.checkCancellation()
            let config = MLModelConfiguration()
            config.computeUnits = units
            let model = try await MLModel.load(contentsOf: folder.appendingPathComponent(name), configuration: config)
            try Task.checkCancellation()
            return model
        }
        progress(0.02)
        let preprocessor = try await component(names.preprocessorFile, units: .cpuOnly)
        progress(0.25)
        let encoder = try await component(ParakeetEncoderPrecision.int8.encoderFileName, units: configuration.computeUnits)
        progress(0.5)
        let decoder = try await component(names.decoderFile, units: configuration.computeUnits)
        progress(0.75)
        let joint = try await component(names.jointV3File, units: configuration.computeUnits)
        progress(1)
        return AsrModels(encoder: encoder, preprocessor: preprocessor, decoder: decoder, joint: joint,
            configuration: configuration, vocabulary: vocabulary, version: .v3)
    }
}
