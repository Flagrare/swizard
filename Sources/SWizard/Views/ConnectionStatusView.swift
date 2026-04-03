import SwiftUI
import Installer

struct ConnectionStatusView: View {
    let isConnected: Bool
    let mode: InstallationCoordinator.TransportMode

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? .green : .red)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.headline)
                .foregroundStyle(isConnected ? .primary : .secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var statusText: String {
        if isConnected {
            "Switch Connected (\(mode.rawValue))"
        } else {
            "Waiting for Switch..."
        }
    }
}
