import SwiftUI
import Installer

struct FileListView: View {
    let files: [TransferProgress.FileProgress]

    var body: some View {
        if files.isEmpty {
            ContentUnavailableView(
                "No files queued",
                systemImage: "tray",
                description: Text("Drop game files above to get started")
            )
        } else {
            List(files) { file in
                FileRowView(file: file)
            }
            .listStyle(.plain)
        }
    }
}
