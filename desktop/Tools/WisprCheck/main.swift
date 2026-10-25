import Foundation
import WisprCore

@main struct Check {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: wisprm-check <chat-completions-endpoint> <local-model>"); return
        }
        let input = "um hello team please review the project notes and send me your feedback thanks"
        let output = try await Polisher().polish(input, style: .professional, configuration: .init(
            endpoint: CommandLine.arguments[1], model: CommandLine.arguments[2]))
        guard output.lowercased().contains("review"), output.lowercased().contains("feedback"),
              output.range(of: "\\bme\\b", options: .regularExpression) != nil,
              !output.hasPrefix("-") else {
            throw NSError(domain: "wisprM", code: 1, userInfo: [NSLocalizedDescriptionKey: "The local model lost the original intent."])
        }
        let report: [String: Any] = ["input": input, "output": output, "model": CommandLine.arguments[2], "passed": true]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
