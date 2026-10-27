# PlayStatus

Eine Mac-App, mit der Discord „Spielt …“ für ein beliebiges Spiel anzeigt, auch wenn du es gar nicht spielst oder nicht installiert hast. Sie ist ein Nachbau der Windows-App [iamlaunch](https://iamlaunch.com/) für macOS.

- Durchsuchbarer Katalog aller Spiele, die Discord kennt, mit echtem Namen und Icon
- Ein Klick, und dein Discord-Profil zeigt „Spielt *Spiel*“ samt Spielzeit
- Symbol in der Menüleiste: Status sehen, stoppen, Fenster öffnen
- Verbindet sich automatisch neu, wenn Discord neu gestartet wird

Die App nutzt dafür die offizielle lokale Rich-Presence-Schnittstelle der Discord-Desktop-App, also dieselbe, über die Spiele ihren Status melden. Sie braucht keinen Discord-Token und keinen Login, und nichts verlässt deinen Rechner, außer dem Download der Spieleliste von Discord.

## Voraussetzungen

- macOS 13 Ventura oder neuer
- Die Discord-Desktop-App (im Browser funktioniert es nicht)
- Xcode oder nur die Command Line Tools: `xcode-select --install`

## Bauen und starten

```bash
git clone https://github.com/keckamreck/iamlaunch.git
cd iamlaunch
./scripts/build-app.sh
open build/PlayStatus.app
```

Danach kannst du `build/PlayStatus.app` in den Programme-Ordner ziehen.

Für die Entwicklung geht es auch ohne App-Bundle: `swift run PlayStatus`.

## Benutzung

1. Discord starten.
2. PlayStatus öffnen und ein Spiel suchen.
3. Auf **Anzeigen** klicken. Oben steht dann „Discord zeigt den Status an“.
4. **Stoppen** entfernt den Status wieder.

Discord zeigt den Status nur, solange PlayStatus läuft. Schließt du das Fenster, läuft die App in der Menüleiste weiter (Gamecontroller-Symbol). Über **PlayStatus beenden** im Menü verschwindet der Status.

### Wenn Discord nichts anzeigt

- In Discord unter **Einstellungen → Aktivitätsprivatsphäre** muss „Deine Aktivität mit anderen teilen“ (Aktivitätsstatus) eingeschaltet sein.
- Die Meldung „Discord-App nicht gefunden“ heißt: Die Desktop-App läuft nicht. PlayStatus versucht es alle 5 Sekunden erneut.
- Die Meldung „Discord hat abgelehnt: …“ heißt: Discord akzeptiert dieses Spiel nicht. Probier ein anderes.

## So funktioniert es

Die Discord-Desktop-App öffnet einen lokalen Socket (`$TMPDIR/discord-ipc-0`), über den Programme ihren Rich-Presence-Status setzen ([Discord-Doku](https://docs.discord.com/developers/topics/rpc)). PlayStatus verbindet sich dort mit der Discord-Anwendungs-ID des gewählten Spiels und sendet `SET_ACTIVITY` mit der Startzeit. Discord zeigt dann Name und Icon dieser Anwendung als gespieltes Spiel.

Der Katalog kommt aus Discords Liste erkennbarer Spiele (`https://discord.com/api/v9/applications/detectable`). Er wird unter `~/Library/Application Support/PlayStatus/` zwischengespeichert, damit die App auch offline startet.

| Teil | Inhalt |
| --- | --- |
| `Sources/PresenceCore` | Logik ohne Oberfläche: IPC-Protokoll, Verbindung, Wiederverbinden, Katalog und Suche |
| `Sources/PlayStatus` | SwiftUI-App: Fenster und Menüleiste |
| `Tests/PresenceCoreTests` | Tests, u. a. gegen einen nachgebauten Discord-Socket |

## Grenzen

- **Keine Discord-Quests.** PlayStatus setzt nur den angezeigten Status, Quests werden damit nicht abgeschlossen.
- Einen Spielstatus anzuzeigen, ohne zu spielen, kann gegen Discords Nutzungsbedingungen verstoßen. Die Nutzung erfolgt auf eigene Verantwortung.
- Die App ist nicht für den App Store gedacht: Die App-Sandbox würde den Zugriff auf den Discord-Socket blockieren.

## Tests

```bash
swift test
```

Die Tests von `PresenceCore` laufen auch unter Linux, z. B. mit Docker:

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.0 swift test
```
