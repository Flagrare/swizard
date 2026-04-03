import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    private static let supportedExtensions: Set<String> = ["nsp", "nsz", "xci", "xcz"]

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Drop .nsp / .xci files here")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
                return true
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let data = await loadFileURLData(from: provider),
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   Self.supportedExtensions.contains(url.pathExtension.lowercased()) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                await MainActor.run { onDrop(urls) }
            }
        }
    }

    private func loadFileURLData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
