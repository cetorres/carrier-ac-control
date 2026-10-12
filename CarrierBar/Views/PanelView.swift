import SwiftUI

/// The panel that opens from the menu bar.
struct PanelView: View {
    @Environment(ThermostatStore.self) private var store

    var body: some View {
        Group {
            switch store.phase {
            case .starting:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .signedOut:
                SignInView()
            case .signedIn:
                SignedInPanel()
            }
        }
        .frame(width: 340)
    }
}

private struct SignedInPanel: View {
    @Environment(ThermostatStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let message = store.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.thermostats.isEmpty {
                emptyState
            } else {
                ForEach(store.thermostats) { thermostat in
                    ThermostatCard(thermostat: thermostat)
                }
            }

            Divider()
            footer
        }
        .padding(14)
        .onAppear { store.refreshIfStale() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Carrier Smart Thermostat")
                    .font(.headline)
                HStack(spacing: 5) {
                    if store.isLive {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .help("Receiving live updates")
                    }
                    Text(statusText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                Group {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("Refresh")
        }
    }

    private var statusText: String {
        if let lastUpdated = store.lastUpdated {
            return "Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
        }
        return store.isRefreshing ? "Loading…" : "Not updated yet"
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.isRefreshing {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else if store.errorMessage == nil {
            Text("No thermostats were found on this account.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let username = store.username {
                Text(username)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Sign Out") {
                Task { await store.signOut() }
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}
