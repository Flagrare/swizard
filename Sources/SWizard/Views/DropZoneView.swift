import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DropZoneView: View {
    let onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        dropArea
            .contentShape(Rectangle())
            .onTapGesture { openFilePicker() }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
                return true
            }
    }

    private var dropArea: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay { dropLabel }
    }

    private var dropLabel: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Drop .nsp / .xci files here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("or Browse...") { openFilePicker() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = DropFileFilter.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.message = "Select game files to install"

        if panel.runModal() == .OK {
            let urls = panel.urls.filter {
                DropFileFilter.supportedExtensions.contains($0.pathExtension.lowercased())
            }
            if !urls.isEmpty {
                onDrop(urls)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let data = await loadFileURLData(from: provider),
                   let url = DropFileFilter.resolveSupportedURL(fromFileURLData: data) {
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
