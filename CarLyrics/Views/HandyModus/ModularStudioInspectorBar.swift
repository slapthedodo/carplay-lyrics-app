// MARK: - ModularStudioInspectorBar.swift
// Schwebende Studio-Steuerleiste mit Nudge D-Pad, Scale-Steppern & Ladedruck-Settings
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import UIKit

public struct ModularStudioInspectorBar: View {
    public var isLandscape: Bool = false
    @ObservedObject private var studio = HandyLayoutStudioManager.shared
    @State private var showExportAlert: Bool = false

    public init(isLandscape: Bool = false) {
        self.isLandscape = isLandscape
    }

    private var selectedId: String? {
        studio.selectedWidgetId
    }

    private var selectedTransform: WidgetFreeformTransform? {
        guard let id = selectedId else { return nil }
        return studio.transform(for: id, isLandscape: isLandscape)
    }

    public var body: some View {
        VStack(spacing: 8) {
            if let id = selectedId, let transform = selectedTransform {
                selectedWidgetInspector(id: id, transform: transform)
            } else {
                idleStudioBar
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.cyan.opacity(0.35), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.7), radius: 14, y: 4)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .alert("Layout-JSON kopiert!", isPresented: $showExportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Die Konfiguration wurde in die Zwischenablage kopiert. Du kannst sie jetzt einfach im Chat einfügen und senden!")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Inspector wenn ein Widget gewählt ist
    // ─────────────────────────────────────────────────────────────────────────

    private func selectedWidgetInspector(id: String, transform: WidgetFreeformTransform) -> some View {
        VStack(spacing: 8) {
            // Header: Titel + Schließen
            HStack {
                HStack(spacing: 5) {
                    Circle().fill(Color.cyan).frame(width: 6, height: 6)
                    Text("Widget: \(widgetDisplayName(id))")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text("X:\(Int(transform.x)) Y:\(Int(transform.y))")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        studio.selectedWidgetId = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }

            // D-Pad Nudge & Scale Zeile
            HStack(spacing: 12) {
                // Fein-Justierung D-Pad (Nudge)
                HStack(spacing: 4) {
                    nudgeButton(icon: "arrow.left", dx: -6, dy: 0, id: id)
                    VStack(spacing: 4) {
                        nudgeButton(icon: "arrow.up", dx: 0, dy: -6, id: id)
                        nudgeButton(icon: "arrow.down", dx: 0, dy: 6, id: id)
                    }
                    nudgeButton(icon: "arrow.right", dx: 6, dy: 0, id: id)
                }

                Divider().frame(height: 30).background(Color.white.opacity(0.15))

                // Skalierung Stepper
                HStack(spacing: 6) {
                    Button {
                        studio.setScale(id: id, isLandscape: isLandscape, scale: transform.scale - 0.08)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 12, weight: .black))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.10), in: Circle())
                    }

                    Text("\(Int(round(transform.scale * 100)))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 44)

                    Button {
                        studio.setScale(id: id, isLandscape: isLandscape, scale: transform.scale + 0.08)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 12, weight: .black))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.10), in: Circle())
                    }
                }

                Spacer()

                // Einzel-Reset
                Button("Zentrieren") {
                    withAnimation {
                        studio.resetWidget(id: id, isLandscape: isLandscape)
                    }
                }
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.18), in: Capsule())
            }

            // Spezial-Optionen wenn Ladedruck-Balken gewählt ist
            if id == "w_boost" {
                VStack(spacing: 6) {
                    // Ausrichtung: Quer / Hochkant / Rund
                    HStack(spacing: 4) {
                        Text("Stil:")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                        ForEach(BoostWidgetOrientation.allCases, id: \.self) { ori in
                            Button {
                                studio.updateBoostConfig { $0.orientation = ori }
                            } label: {
                                Text(ori.rawValue)
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3.5)
                                    .background(
                                        studio.boostConfig.orientation == ori ? Color.orange : Color.white.opacity(0.08),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(studio.boostConfig.orientation == ori ? .black : .white)
                            }
                        }
                    }

                    // Dicke: Dünn / Normal / Dick / Massiv
                    if studio.boostConfig.orientation != .arc {
                        HStack(spacing: 4) {
                            Text("Dicke:")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                            ForEach(BoostWidgetThickness.allCases, id: \.self) { thick in
                                Button {
                                    studio.updateBoostConfig { $0.thickness = thick }
                                } label: {
                                    Text(thick.rawValue)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            studio.boostConfig.thickness == thick ? Color.cyan : Color.white.opacity(0.08),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(studio.boostConfig.thickness == thick ? .black : .white)
                                }
                            }
                        }
                    }
                }
                .padding(6)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func nudgeButton(icon: String, dx: CGFloat, dy: CGFloat, id: String) -> some View {
        Button {
            studio.nudge(id: id, isLandscape: isLandscape, dx: dx, dy: dy)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Idle Bar (kein Widget aktiv selektiert)
    // ─────────────────────────────────────────────────────────────────────────

    private var idleStudioBar: some View {
        HStack(spacing: 8) {
            // Modus Umschalter (Verschieben vs Scrollen)
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    studio.isScrollModeInStudio.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: studio.isScrollModeInStudio ? "hand.draw.fill" : "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(studio.isScrollModeInStudio ? "Scroll-Modus" : "Anordnungs-Modus")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                }
                .foregroundStyle(studio.isScrollModeInStudio ? .black : .cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(studio.isScrollModeInStudio ? Color.yellow : Color.cyan.opacity(0.2), in: Capsule())
            }

            Spacer()

            // JSON Exportieren
            Button {
                let json = studio.exportJSON()
                UIPasteboard.general.string = json
                showExportAlert = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "doc.on.doc.fill")
                    Text("Export")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.cyan.opacity(0.15), in: Capsule())
            }

            // Alle Zurücksetzen
            Button("Reset") {
                withAnimation { studio.resetAll(isLandscape: isLandscape) }
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.15), in: Capsule())

            // Studio Beenden
            Button("Fertig") {
                withAnimation {
                    studio.selectedWidgetId = nil
                    studio.isEditModeActive = false
                }
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.green)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.2), in: Capsule())
        }
    }

    private func widgetDisplayName(_ id: String) -> String {
        switch id {
        case "w_boost":   return "Ladedruck-Balken"
        case "w_rpm":     return "Drehzahlmesser"
        case "w_speed":   return "Digital Speed / Tacho"
        case "w_oil":     return "Öltemperatur"
        case "w_dyno":    return "Live Prüfstand"
        case "w_gforce":  return "G-Kräfte Radar"
        case "w_lyrics":  return "Spotify Songtexte"
        case "w_stats":   return "Telemetrie Stats"
        default:          return id
        }
    }
}
