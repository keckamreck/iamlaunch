import PresenceCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            StatusPanel(model: model)
                .padding()
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Spiel suchen", text: $model.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            Divider()
            catalog
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    @ViewBuilder
    private var catalog: some View {
        switch model.catalogState {
        case .loading:
            ProgressView("Lade Spielekatalog …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 12) {
                Text("Spielekatalog konnte nicht geladen werden")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Erneut versuchen") { model.loadCatalog() }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            let results = model.results
            if results.isEmpty {
                Text("Keine Spiele gefunden")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { game in
                    GameRow(game: game, isActive: model.activeGame?.id == game.id) {
                        model.show(game)
                    }
                }
            }
        }
    }
}

/// The selected game and whether Discord shows it.
struct StatusPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let game = model.activeGame {
                    GameIcon(game: game, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spielt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(game.name)
                            .font(.headline)
                            .lineLimit(1)
                        if let since = model.activeSince {
                            Text(since, style: .timer)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Stoppen") { model.stop() }
                } else {
                    Image(systemName: "gamecontroller")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kein Status aktiv")
                            .font(.headline)
                        Text("Wähle unten ein Spiel aus, das Discord anzeigen soll.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            ConnectionLine(status: model.status)
        }
    }
}

struct ConnectionLine: View {
    let status: PresenceStatus

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Verbinde mit Discord …")
            }
            .font(.callout)
        case .active:
            Label("Discord zeigt den Status an", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .waitingForDiscord:
            Label(
                "Discord-App nicht gefunden. Öffne Discord, PlayStatus verbindet sich automatisch.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
        case .rejected(let message):
            Label("Discord hat abgelehnt: \(message)", systemImage: "xmark.octagon.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }
}

struct GameRow: View {
    let game: Game
    let isActive: Bool
    let onShow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            GameIcon(game: game, size: 28)
            Text(game.name)
                .lineLimit(1)
            Spacer()
            if isActive {
                Label("Aktiv", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Anzeigen", action: onShow)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onShow)
    }
}

struct GameIcon: View {
    let game: Game
    let size: CGFloat

    var body: some View {
        Group {
            if let url = game.iconURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .overlay(
                Image(systemName: "gamecontroller")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
            )
    }
}
