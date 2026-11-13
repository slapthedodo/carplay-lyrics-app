// MARK: - HandyLayoutStudioSettingsView.swift
// Dashboard Studio & Anordnungs-Modus Einstellungen im Setup-Tab
// Erlaubt freies Anordnen, Resizen, Undo, Reset und Export der Layout-Konfiguration
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import UIKit

public struct HandyLayoutStudioSettingsView: View {
    @ObservedObject var obd: OBDManager

    @AppStorage("carlyrics_studio_edit_mode") private var isEditModeActive: Bool = false
    @AppStorage("carlyrics_boost_bar_style")  private var boostBarStyle: String = "standard"
    @AppStorage("carlyrics_widget_order")     private var widgetOrderRaw: String = "w_lyrics,w_gauges,w_gforce,w_stats"

    @State private var copiedSuccess: Bool = false
    @State private var undoSuccess: Bool = false
    @State private var history: [String] = []

    public init(obd: OBDManager) {
        self.obd = obd
    }

    private var widgets: [String] {
        widgetOrderRaw.components(separatedBy: ",").filter { !$0.isEmpty && $0 != "w_gt3" }
    }

    private func widgetTitle(_ id: String) -> (title: String, icon: String, subtitle: String) {
        switch id {
        case "w_lyrics":
            return ("Spotify CarPlay Lyrics", "music.note.list", "Synchronisierte Live-Songtexte")
        case "w_gauges":
            return ("Haupt-Gauges (3er Reihe)", "speedometer", "RPM, Ladedruck & Öltemperatur")
        case "w_gforce":
            return ("G-Kräfte 2D Radar", "circle.dashed", "Quer- & Längsbeschleunigung HUD")
        case "w_stats":
            return ("Telemetrie Stats (8 Kacheln)", "chart.bar.xaxis", "MAF, Ansaugluft, Speed, Abgas")
        default:
            return (id, "square.grid.2x2", "Dashboard Element")
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── 1. Anordnungsmodus Master Toggle ──────────────────────
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "pencil.and.ruler.fill")
                                .font(.title3)
                                .foregroundStyle(Color.cyan)
                            Text("Handy-Dashboard Studio")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Toggle("", isOn: $isEditModeActive)
                                .labelsHidden()
                                .tint(.cyan)
                        }

                        Text("Wenn aktiviert, kannst du im Handy-Tab jedes Widget frei nach oben/unten schieben und skalieren. Ideal um dein individuelles GTI-Cockpit zu bauen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Circle()
                                .fill(isEditModeActive ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(isEditModeActive ? "Anordnungs-Modus AKTIV (im Handy-Tab editierbar)" : "Normaler Anzeige-Modus (gesperrt)")
                                .font(.caption.bold())
                                .foregroundStyle(isEditModeActive ? .green : .secondary)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                // ── 2. Ladedruck-Balken Style Optionen ────────────────────
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Ladedruck-Balken Styling", systemImage: "waveform.path.ecg")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Text("Stelle die Optik des Ladedruck-Balkens auf deine Vorlieben ein:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Ladedruck Stil", selection: $boostBarStyle) {
                            Text("Standard (10pt)").tag("standard")
                            Text("Fett (22pt Gradient)").tag("thick")
                            Text("Schlank (5pt)").tag("thin")
                            Text("Vertikal").tag("vertical")
                        }
                        .pickerStyle(.segmented)

                        // Vorschau Balken
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Vorschau (\(boostBarStyle.capitalized)):")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.secondary)

                            previewBar
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                // ── 3. Widget-Reihenfolge & Schnell-Sortierung ────────────
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Widget-Reihenfolge (Handy-Tab)", systemImage: "list.number")
                            .font(.headline)
                            .foregroundStyle(.cyan)

                        Text("Verschiebe Widgets nach oben oder unten, um die Anordnung festzulegen:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(Array(widgets.enumerated()), id: \.element) { index, widgetId in
                            let info = widgetTitle(widgetId)
                            HStack(spacing: 10) {
                                Image(systemName: info.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.cyan)
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(info.title)
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                    Text(info.subtitle)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                // Up Button
                                Button {
                                    moveWidget(index: index, direction: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(index > 0 ? .white : .secondary.opacity(0.3))
                                        .padding(6)
                                        .background(Color.white.opacity(0.06), in: Circle())
                                }
                                .disabled(index == 0)

                                // Down Button
                                Button {
                                    moveWidget(index: index, direction: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(index < widgets.count - 1 ? .white : .secondary.opacity(0.3))
                                        .padding(6)
                                        .background(Color.white.opacity(0.06), in: Circle())
                                }
                                .disabled(index == widgets.count - 1)
                            }
                            .padding(.vertical, 4)

                            if index < widgets.count - 1 {
                                Divider().opacity(0.2)
                            }
                        }
                    }
                }

                // ── 4. Layout Aktionen: Undo, Reset, JSON Export ─────────
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Layout Aktionen & Teilen", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                            .foregroundStyle(Color(red: 0.95, green: 0.86, blue: 0.48))

                        HStack(spacing: 10) {
                            // Undo Button
                            Button {
                                performUndo()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: undoSuccess ? "checkmark" : "arrow.uturn.backward")
                                    Text("Rückgängig")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(CockpitButtonStyle(color: .secondary))
                            .disabled(history.isEmpty)

                            // Reset Button
                            Button {
                                resetToDefault()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Reset")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(CockpitButtonStyle(color: .red))
                        }

                        // Export / Copy Layout Button
                        Button {
                            copyLayoutJSON()
                        } label: {
                            HStack {
                                Image(systemName: copiedSuccess ? "checkmark.seal.fill" : "doc.on.doc.fill")
                                Text(copiedSuccess ? "Layout kopiert! (JSON)" : "Layout kopieren / senden")
                                    .fontWeight(.bold)
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(CockpitButtonStyle(color: copiedSuccess ? .green : .cyan))

                        Text("Kopiert deine Anordnung als JSON in die Zwischenablage. So kannst du mir den Code direkt im Chat schicken!")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func saveToHistory() {
        history.append(widgetOrderRaw)
        if history.count > 10 { history.removeFirst() }
    }

    private func moveWidget(index: Int, direction: Int) {
        var current = widgets
        let targetIndex = index + direction
        guard targetIndex >= 0 && targetIndex < current.count else { return }

        saveToHistory()
        let item = current.remove(at: index)
        current.insert(item, at: targetIndex)
        widgetOrderRaw = current.joined(separator: ",")
    }

    private func performUndo() {
        guard let prev = history.popLast() else { return }
        widgetOrderRaw = prev
        undoSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            undoSuccess = false
        }
    }

    private func resetToDefault() {
        saveToHistory()
        widgetOrderRaw = "w_lyrics,w_gauges,w_gforce,w_stats"
        boostBarStyle = "standard"
        HandyLayoutStudioManager.shared.resetAll()
    }

    private func copyLayoutJSON() {
        let jsonDict: [String: Any] = [
            "vehicle": "VW Golf 5 GTI EA113 Stage 1",
            "widgetsOrder": widgets,
            "boostBarStyle": boostBarStyle,
            "editModeActive": isEditModeActive,
            "transforms": HandyLayoutStudioManager.shared.transforms.mapValues { [
                "x": $0.x,
                "y": $0.y,
                "widthOffset": $0.widthOffset,
                "heightOffset": $0.heightOffset
            ] },
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: jsonDict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = str
            copiedSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                copiedSuccess = false
            }
        }
    }

    private var previewBar: some View {
        Group {
            switch boostBarStyle {
            case "thick":
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [.cyan, .orange, .red], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 20)
            case "thin":
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [.cyan, .orange, .red], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 5)
            case "vertical":
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [.cyan, .orange, .red], startPoint: .bottom, endPoint: .top))
                        .frame(width: 14, height: 40)
                    Text("1.45 bar (Peak)")
                        .font(.caption2.bold())
                        .foregroundStyle(.cyan)
                    Spacer()
                }
            default:
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [.cyan, .orange, .red], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 10)
            }
        }
    }
}
