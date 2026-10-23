import SwiftUI
import WisprCore

struct ModelStorageView: View {
    let modelID: String
    let engine: SpeechEngine
    let refresh: String
    @State private var status: ModelStorageStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(SpeechModelCatalog.bundled.downloadSize(modelID))
                Spacer()
                if let status {
                    Label(status.complete ? "Available locally" : status.exists ? "Incomplete or unverified" : "Not downloaded",
                          systemImage: status.complete ? "checkmark.circle" : "internaldrive")
                }
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
            if let status {
                if let location = status.location {
                    Text(status.exists ? "LOCAL LOCATION" : "DOWNLOAD LOCATION")
                        .font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.muted)
                    Text(location.path).font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if let bytes = status.bytes {
                            Text(SpeechModelCatalog.size(bytes) + " local files")
                        }
                        Spacer()
                        if status.exists {
                            Button("Show in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.path) }
                        }
                        Button("Refresh") { refreshStatus() }
                    }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                } else {
                    Text("Enter an absolute folder or a model ID to see its storage location.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            } else {
                Text("Checking local storage…").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }
        .padding(12).background(Palette.green.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: modelID + "|" + engine.rawValue + "|" + refresh + "|" + refreshToken.uuidString) {
            status = nil
            let location = SpeechModelCatalog.bundled.location(for: modelID)
            let engine = engine
            let scan = Task.detached(priority: .utility) { ModelStorageStatus.inspect(location: location, engine: engine) }
            let result = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
            if !Task.isCancelled { status = result }
        }
    }

    @State private var refreshToken = UUID()
    private func refreshStatus() { refreshToken = UUID() }
}
