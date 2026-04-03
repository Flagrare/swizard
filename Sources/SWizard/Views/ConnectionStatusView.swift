import SwiftUI

struct ConnectionStatusView: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? .green : .red)
                .frame(width: 10, height: 10)

            Text(isConnected ? "Switch Connected" : "Waiting for Switch...")
                .font(.headline)
                .foregroundStyle(isConnected ? .primary : .secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
