// MARK: - ModularStudioInspectorBar.swift
// Schwebende Studio-Steuerleiste mit 1er-Schritt D-Pad, Sub-Target Steuerung (Gesamt/Balken/Text),
// Widget-Katalog (Add/Remove) und immer sichtbarem "Fertig"-Button
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import UIKit

public struct ModularStudioInspectorBar: View {
    public var isLandscape: Bool = false
    @ObservedObject private var studio = HandyLayoutStudioManager.shared
    @State private var showExportAlert: Bool = false
    @State private var showCatalogSheet: Bool = false

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
                .fill(Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.cyan.opacity(0.35), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.75), radius: 14, y: 4)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .sheet(isPresented: $showCatalogSheet) {
            StudioWidgetCatalogSheet(isLandscape: isLandscape)
        }
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
            // Header: Titel + SubTarget Switcher + Löschen + Fertig
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Circle().fill(Color.cyan).frame(width: 6, height: 6)
                    Text(widgetDisplayName(id))
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer()

                // Sub-Target Picker (Gesamt | Balken | Text)
                HStack(spacing: 2) {
                    ForEach(StudioEditSubTarget.allCases) { sub in
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                studio.activeSubTarget = sub
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: sub.icon)
                                    .font(.system(size: 7.5, weight: .bold))
                                Text(sub.rawValue)
                                    .font(.system(size: 8.5, weight: studio.activeSubTarget == sub ? .black : .bold))
                            }
                            .foregroundStyle(studio.activeSubTarget == sub ? .black : .white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                studio.activeSubTarget == sub ? Color.cyan : Color.white.opacity(0.10),
                                in: Capsule()
                            )
                        }
                    }
                }
                .padding(2)
                .background(Color.white.opacity(0.06), in: Capsule())

                // Widget entfernen
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        studio.setWidgetVisible(id: id, isLandscape: isLandscape, isVisible: false)
                        studio.selectedWidgetId = nil
                    }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.red)
                        .padding(5)
                        .background(Color.red.opacity(0.18), in: Circle())
                }

                // Fertig (immer sichtbar zum direkten Schließen)
                Button("Fertig") {
                    withAnimation {
                        studio.selectedWidgetId = nil
                        studio.isEditModeActive = false
                    }
                }
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green, in: Capsule())
            }

            // D-Pad Nudge & Scale Zeile
            HStack(spacing: 10) {
                // Fein-Justierung D-Pad (1er-Koordinatenschritte!)
                HStack(spacing: 3) {
                    nudgeButton(icon: "arrow.left", dx: -1, dy: 0, id: id)
                    VStack(spacing: 3) {
                        nudgeButton(icon: "arrow.up", dx: 0, dy: -1, id: id)
                        nudgeButton(icon: "arrow.down", dx: 0, dy: 1, id: id)
                    }
                    nudgeButton(icon: "arrow.right", dx: 1, dy: 0, id: id)
                }

                // Koordinaten & Skala Anzeige
                VStack(alignment: .leading, spacing: 2) {
                    Text(subTargetCoordsText(transform))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Text("Schritt: 1 pt")
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(minWidth: 70, alignment: .leading)

                Divider().frame(height: 28).background(Color.white.opacity(0.15))

                // Skalierung Stepper (±5%)
                HStack(spacing: 4) {
                    Button {
                        studio.stepScale(id: id, isLandscape: isLandscape, delta: -0.05)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .black))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.10), in: Circle())
                    }

                    Text(subTargetScaleText(transform))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 42)

                    Button {
                        studio.stepScale(id: id, isLandscape: isLandscape, delta: 0.05)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .black))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.10), in: Circle())
                    }
                }

                Spacer()

                // Einzel-Reset
                Button("Reset") {
                    withAnimation {
                        studio.resetSubTarget(id: id, isLandscape: isLandscape)
                    }
                }
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.18), in: Capsule())
            }
        }
    }

    private func nudgeButton(icon: String, dx: CGFloat, dy: CGFloat, id: String) -> some View {
        Button {
            studio.nudge(id: id, isLandscape: isLandscape, dx: dx, dy: dy)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func subTargetCoordsText(_ t: WidgetFreeformTransform) -> String {
        switch studio.activeSubTarget {
        case .whole: return "X:\(Int(t.x)) Y:\(Int(t.y))"
        case .bar:   return "B-X:\(Int(t.barOffsetX)) B-Y:\(Int(t.barOffsetY))"
        case .text:  return "T-X:\(Int(t.textOffsetX)) T-Y:\(Int(t.textOffsetY))"
        }
    }

    private func subTargetScaleText(_ t: WidgetFreeformTransform) -> String {
        switch studio.activeSubTarget {
        case .whole: return "\(Int(round(t.scale * 100)))%"
        case .bar:   return "\(Int(round(t.barScale * 100)))%"
        case .text:  return "\(Int(round(t.textScale * 100)))%"
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
                    Text(studio.isScrollModeInStudio ? "Scrollen" : "Anordnen")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                }
                .foregroundStyle(studio.isScrollModeInStudio ? .black : .cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(studio.isScrollModeInStudio ? Color.yellow : Color.cyan.opacity(0.2), in: Capsule())
            }

            // Widget Hinzufügen / Katalog
            Button {
                showCatalogSheet = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus.circle.fill")
                    Text("+ Widget")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.cyan.opacity(0.18), in: Capsule())
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

            // Studio Beenden (immer vorhanden!)
            Button("Fertig") {
                withAnimation {
                    studio.selectedWidgetId = nil
                    studio.isEditModeActive = false
                }
            }
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.green, in: Capsule())
            .shadow(color: Color.green.opacity(0.5), radius: 6)
        }
    }

    private func widgetDisplayName(_ id: String) -> String {
        let catalog = isLandscape ? HandyLayoutStudioManager.landscapeWidgetsCatalog : HandyLayoutStudioManager.portraitWidgetsCatalog
        if let found = catalog.first(where: { $0.id == id }) {
            return found.title
        }
        return id
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Studio Widget Catalog Sheet (Add / Remove Widgets)
// ─────────────────────────────────────────────────────────────────────────────

public struct StudioWidgetCatalogSheet: View {
    public var isLandscape: Bool = false
    @ObservedObject private var studio = HandyLayoutStudioManager.shared
    @Environment(\.dismiss) private var dismiss

    private var catalog: [StudioWidgetDefinition] {
        isLandscape ? HandyLayoutStudioManager.landscapeWidgetsCatalog : HandyLayoutStudioManager.portraitWidgetsCatalog
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.08, blue: 0.12).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(catalog) { widget in
                            let isVisible = studio.isWidgetVisible(id: widget.id, isLandscape: isLandscape)

                            HStack(spacing: 12) {
                                Image(systemName: widget.icon)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(isVisible ? Color.cyan : Color.white.opacity(0.3))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(widget.title)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(widget.subtitle)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if isVisible {
                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            studio.setWidgetVisible(id: widget.id, isLandscape: isLandscape, isVisible: false)
                                            if studio.selectedWidgetId == widget.id {
                                                studio.selectedWidgetId = nil
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark")
                                            Text("Aktiv")
                                        }
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.green.opacity(0.18), in: Capsule())
                                    }
                                } else {
                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            studio.setWidgetVisible(id: widget.id, isLandscape: isLandscape, isVisible: true)
                                            studio.selectedWidgetId = widget.id
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus")
                                            Text("Hinzufügen")
                                        }
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.cyan, in: Capsule())
                                    }
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(isVisible ? Color.cyan.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Widgets verwalten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        dismiss()
                    }
                    .foregroundStyle(.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
