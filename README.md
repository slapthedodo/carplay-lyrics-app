# CarLyrics 🎵🏎️

> **Synchronisierte Songtexte (LRC) & Performance-Telemetrie live in CarPlay & der Dynamic Island**

CarLyrics ist eine native iOS-Anwendung in Swift / SwiftUI mit Widget Extension (ActivityKit), die das Fahrerlebnis auf das nächste Level hebt. Die App erkennt die aktuelle Wiedergabe auf dem iPhone, holt synchronisierte Songtexte über LRCLIB und rendert diese zusammen mit Live-Telemetriedaten (Öltemperatur-Simulation & G-Kräfte) in der Dynamic Island, auf dem Sperrbildschirm und im CarPlay Dashboard.

---

## ✨ Features

1. **Synchronisierte Songtexte (LRC)**:
   - Synchroner Abruf über die freie [LRCLIB](https://lrclib.net)-API mit automatischem Fallback auf Titelsuche.
   - Hochpräziser Parser für Zeitstempel im Format `[mm:ss.xx]`.
   - Lokaler 100ms-Timer für flüssiges Umschalten der Zeilen mit Rate-Limiting für ActivityKit-Updates.

2. **Performance & Motor-Warmfahr-Assistent**:
   - Realistisches Aufwärmmodell (asymptotische Kurve) für 2.0L TFSI Turbomotoren (Ziel: 90°C).
   - 3 Phasen: **Kalt** (< 60°C, blau), **Aufwärmen** (60–79°C, orange), **Bereit** (≥ 80°C, grün) inkl. haptischem Feedback.
   - Modi für Kaltstart (20°C) und Warmstart (45°C).

3. **Echtzeit G-Kräfte (CoreMotion)**:
   - Erfassung der Beschleunigungskräfte über `CMMotionManager` bei 10 Hz mit Tiefpassfilterung.
   - Berechnung kombinierter horizontaler G-Kräfte, Vektoren (`x`, `y`) und Spitzenwerten (`peakG`).
   - Nullpunkt-Kalibrierung für die Handy-Halterung im Fahrzeug.

4. **Dynamic Island & CarPlay / Lock Screen Integration**:
   - **Compact Leading**: Öltemperatur-Badge mit dynamischem Farb- und Fortschrittsring.
   - **Compact Trailing**: Live G-Force Anzeige mit Farbabstufungen.
   - **Expanded & CarPlay**: Sport-Telemetriebalken oben, darunter kontrastreiche Lyrics (20pt fett für `currentLine`, 15pt für `nextLine`).

5. **Audio Keep-Alive im Hintergrund**:
   - `BackgroundKeepAliveManager` mit unhörbarem `AVAudioSession` Loop (`.mixWithOthers`), damit iOS die App während der Fahrt nicht terminiert, während Musik (Spotify / Apple Music) nahtlos weiterläuft.

---

## 🛠️ Technische Voraussetzungen

- **iOS**: 17.0+ (Deployment Target)
- **Xcode**: 15.3+
- **Geräte**: Optimiert für iPhone mit Dynamic Island (z. B. iPhone 14 Pro / Pro Max und neuer) und Apple CarPlay.

---

## 🚀 Setup & Installation

1. Repository klonen:
   ```bash
   git clone https://github.com/slapthedodo/carplay-lyrics-app.git
   ```
2. Projekt in Xcode öffnen:
   ```bash
   open CarLyrics.xcodeproj
   ```
3. **Signing & Capabilities**:
   - Wähle dein Apple Developer Team unter *Signing & Capabilities* aus.
   - Passe den Bundle Identifier an deine Domain an (z. B. `com.deinname.CarLyrics` und `com.deinname.CarLyrics.widget`).
   - Stelle sicher, dass `Background Modes` (Audio) und `Supports Live Activities` aktiviert sind.
4. **Target Membership**:
   - Achte darauf, dass `LyricsModels.swift` sowohl im Haupt-Target (`CarLyrics`) als auch im Widget-Target (`CarLyricsWidgetExtension`) eingebunden ist.
5. Auf dein iPhone übertragen und starten.

---

## 🧪 Test-Modus (Mock Injector)

Über das Kolben-Symbol (**⚗**) in der Navigationsleiste der App kann jederzeit ein Test-Track samt LRC-Songtext eingespeist werden, um die Live Activity und Zeilenwechsel ohne aktive Musikwiedergabe zu testen.
