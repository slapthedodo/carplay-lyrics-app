// MARK: - SettingsTabView.swift
// Einstellungs-Tab (Dynamic Island, Shortcuts, Latenz, Spotify, Sensoren)
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import UserNotifications

public struct SettingsTabView: View {
    @ObservedObject var spotify : SpotifyManager
    @ObservedObject var obd     : OBDManager
    @ObservedObject var observer: MusicObserver
    @State private var tokenInput: String = ""
    @State private var resetSuccess: Bool = false

    public init(spotify: SpotifyManager, obd: OBDManager, observer: MusicObserver) {
        self.spotify = spotify
        self.obd = obd
        self.observer = observer
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Dynamic Island & Live Activity Steuerung
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Dynamic Island & Sperrbildschirm", systemImage: "capsule.fill")
                            .font(.headline)
                            .foregroundStyle(.cyan)

                        Text("Die Dynamic Island aktualisiert Öltemperatur, Ladedruck, G-Kraft und Songtexte live. Wenn du das Auto verlässt, schließt sie sich nach 10 Sekunden automatisch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Live Fahrzeug-Status & Auto-Close Watchdog
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-Erkennung (CarPlay / BT / OBD):")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                if observer.isCarOrActiveConnected {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.green).frame(width: 8, height: 8)
                                        Text("Fahrzeug / App aktiv")
                                            .font(.caption.bold())
                                            .foregroundStyle(.green)
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                                        let rem = max(0, 10 - observer.disconnectedSeconds)
                                        Text(rem > 0 ? "Getrennt (Schließt in \(rem)s)" : "Getrennt (Beendet ✓)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            Spacer()
                            Toggle("", isOn: $observer.autoDismissEnabled)
                                .labelsHidden()
                                .tint(.cyan)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                        HStack {
                            Button {
                                Task {
                                    await observer.resetLiveActivities()
                                }
                                resetSuccess = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    resetSuccess = false
                                }
                            } label: {
                                Label(resetSuccess ? "Zurückgesetzt ✓" : "Dynamic Island zurücksetzen",
                                      systemImage: resetSuccess ? "checkmark.circle.fill" : "arrow.clockwise.circle.fill")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(resetSuccess ? .green : .white)
                            }
                            .buttonStyle(CockpitButtonStyle(color: resetSuccess ? .green : .cyan))

                            Spacer()

                            Button {
                                Task {
                                    await observer.reattachOrCreateLiveActivity()
                                }
                            } label: {
                                Label("Neu starten", systemImage: "play.circle.fill")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(CockpitButtonStyle(color: .secondary))
                        }
                    }
                }

                // Apple Kurzbefehle & Automation
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Apple Kurzbefehle (Shortcuts) & Automation", systemImage: "bolt.badge.automatic.fill")
                            .font(.headline)
                            .foregroundStyle(.purple)

                        Text("Du kannst die Dynamic Island jetzt direkt über Apple Kurzbefehle, Siri oder automatisierte Auslöser steuern:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.purple).font(.caption)
                                Text("Aktionen: 'Dynamic Island beenden' & 'Dynamic Island starten'")
                                    .font(.caption.bold())
                            }
                            HStack {
                                Image(systemName: "link").foregroundStyle(.cyan).font(.caption)
                                Text("URL-Befehle: carlyrics://stop und carlyrics://start")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }
                        }
                        .padding(8)
                        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                        Text("Empfohlene Automation beim Fahren:")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        Text("In Kurzbefehle > Automation > 'Wenn CarPlay trennt' > Aktion 'Dynamic Island beenden'. Sobald du den Schlüssel ziehst, schließt sich die Dynamic Island automatisch!")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    await observer.endAllLiveActivities()
                                    BackgroundKeepAliveManager.shared.stop()
                                    MotionManager.shared.stop()
                                    WarmupManager.shared.stop()
                                }
                            } label: {
                                Label("Jetzt beenden (Aus)", systemImage: "stop.circle.fill")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(CockpitButtonStyle(color: .red))

                            Button {
                                Task {
                                    BackgroundKeepAliveManager.shared.start()
                                    MotionManager.shared.start()
                                    WarmupManager.shared.start()
                                    await observer.reattachOrCreateLiveActivity()
                                    observer.startTelemetryHeartbeat()
                                }
                            } label: {
                                Label("Jetzt starten (Ein)", systemImage: "play.circle.fill")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(CockpitButtonStyle(color: .green))
                        }
                    }
                }

                // Benachrichtigung bei Erreichen der Betriebstemperatur
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Betriebstemperatur Benachrichtigung", systemImage: "bell.badge.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        Text("Sobald das Öl 80°C erreicht hat und der Motor betriebsbereit ist, erhältst du automatisch eine Push-Mitteilung mit Signalton – auch bei gesperrtem Bildschirm oder im Hintergrund.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            WarmupManager.shared.requestNotificationPermission()
                            let content = UNMutableNotificationContent()
                            content.title = "Motor ist warm"
                            content.body = "Öltemperatur: 80°C"
                            content.sound = .default
                            content.interruptionLevel = .timeSensitive
                            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                            let req = UNNotificationRequest(identifier: "test_warm_engine", content: content, trigger: trigger)
                            UNUserNotificationCenter.current().add(req)
                        } label: {
                            Label("Test-Benachrichtigung senden", systemImage: "paperplane.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(CockpitButtonStyle(color: .green))
                    }
                }

                // 2. CarPlay Audio-Verzögerung
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("CarPlay Audio-Latenz Kompensation", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .foregroundStyle(.cyan)

                        Text("Wireless CarPlay & Bluetooth puffern Audio um 2–3 Sekunden. Dieser Regler synchronisiert die Songtexte exakt auf den Zeitpunkt, an dem der Ton aus deinen Autolautsprechern kommt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Offset:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(String(format: "-%.1f s", spotify.carPlayDelayCompensation))
                                .font(.system(.title3, design: .monospaced, weight: .bold))
                                .foregroundStyle(.cyan)
                        }

                        Slider(value: $spotify.carPlayDelayCompensation, in: 0.0...4.0, step: 0.1)
                            .tint(.cyan)

                        HStack {
                            Text("0.0s (USB Kabel)").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("2.5s (Wireless CarPlay)").font(.caption2.bold()).foregroundStyle(.cyan)
                            Spacer()
                            Text("4.0s").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                // 3. G-Kraft Sensor & Maximalwert
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("G-Kraft Sensor & Maximalwert")
                            .font(.headline)
                            .foregroundStyle(.cyan)

                        Text("Stelle die maximale G-Kraft passend zu deinem Fahrzeug ein. Erschütterungen über diesem Wert werden gefiltert und der G-Meter skaliert dynamisch darauf.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Max. G-Kraft Limit:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(String(format: "%.2f G", MotionManager.shared.maxG))
                                .font(.system(.title3, design: .monospaced, weight: .bold))
                                .foregroundStyle(.cyan)
                        }

                        Slider(value: Binding(
                            get: { MotionManager.shared.maxG },
                            set: { MotionManager.shared.maxG = $0 }
                        ), in: 0.5...3.0, step: 0.05)
                        .tint(.cyan)

                        HStack {
                            Text("0.5G (Komfort)").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("1.2G (TFSI Serie)").font(.caption2.bold()).foregroundStyle(.cyan)
                            Spacer()
                            Text("3.0G (Rennstrecke)").font(.caption2).foregroundStyle(.secondary)
                        }

                        HStack {
                            Button {
                                MotionManager.shared.resetPeak()
                            } label: {
                                Label("Peak Reset", systemImage: "arrow.counterclockwise")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(CockpitButtonStyle(color: .secondary))

                            Spacer()

                            Button {
                                MotionManager.shared.calibrate()
                            } label: {
                                Label("Nullpunkt kalibrieren", systemImage: "scope")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(CockpitButtonStyle(color: .cyan))
                        }
                    }
                }

                // 4. Spotify Verbindung
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Spotify Web API", systemImage: "waveform.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        Text("Da du nur Spotify nutzt, liest CarLyrics den aktuellen Song, die Millisekunden-Position und Pausen direkt von deinem Spotify-Konto.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if spotify.isAuthenticated {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text("Mit Spotify verbunden").font(.subheadline.bold())
                                Spacer()
                                Button("Trennen") {
                                    spotify.accessToken = ""
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                            }
                        } else {
                            VStack(spacing: 10) {
                                SecureField("Spotify OAuth Access Token hier einfügen", text: $tokenInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)

                                Button {
                                    spotify.accessToken = tokenInput
                                    spotify.startPolling()
                                } label: {
                                    Label("Token speichern & verbinden", systemImage: "arrow.right.circle.fill")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(CockpitButtonStyle(color: .green))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}
