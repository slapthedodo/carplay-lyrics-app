// MARK: - HandyLayoutStudioManager.swift
// Freies 2D Studio-Layout-System für das Handy-Cockpit (Portrait & Landscape)
// Ermöglicht freies Verschieben (X, Y), Skalieren, Resizen, Nudge D-Pad (1er-Schritte),
// getrennte Balken- & Text-Transformationen, Widget-Katalog (Add/Remove) und JSON Export
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public enum StudioEditSubTarget: String, CaseIterable, Identifiable {
    case whole = "Gesamt"
    case bar   = "Balken"
    case text  = "Text"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .whole: return "rectangle.dashed"
        case .bar:   return "chart.bar.xaxis"
        case .text:  return "textformat.size"
        }
    }
}

public struct WidgetFreeformTransform: Codable, Equatable {
    // ── 1. Gesamtgröße & Position (mit Hintergrund) ──
    public var x: CGFloat = 0
    public var y: CGFloat = 0
    public var widthOffset: CGFloat = 0
    public var heightOffset: CGFloat = 0
    public var scale: CGFloat = 1.0
    public var zIndex: Double = 1.0
    public var isVisible: Bool = true

    // ── 2. Balken / Anzeigen (Gauges, Bars, Arcs) ──
    public var barScale: CGFloat = 1.0
    public var barOffsetX: CGFloat = 0
    public var barOffsetY: CGFloat = 0
    public var barWidthOffset: CGFloat = 0
    public var barHeightOffset: CGFloat = 0

    // ── 3. Text / Werte (Labels, Zahlen, Readouts) ──
    public var textScale: CGFloat = 1.0
    public var textOffsetX: CGFloat = 0
    public var textOffsetY: CGFloat = 0

    public init(
        x: CGFloat = 0,
        y: CGFloat = 0,
        widthOffset: CGFloat = 0,
        heightOffset: CGFloat = 0,
        scale: CGFloat = 1.0,
        zIndex: Double = 1.0,
        isVisible: Bool = true,
        barScale: CGFloat = 1.0,
        barOffsetX: CGFloat = 0,
        barOffsetY: CGFloat = 0,
        barWidthOffset: CGFloat = 0,
        barHeightOffset: CGFloat = 0,
        textScale: CGFloat = 1.0,
        textOffsetX: CGFloat = 0,
        textOffsetY: CGFloat = 0
    ) {
        self.x = x
        self.y = y
        self.widthOffset = widthOffset
        self.heightOffset = heightOffset
        self.scale = scale
        self.zIndex = zIndex
        self.isVisible = isVisible
        self.barScale = barScale
        self.barOffsetX = barOffsetX
        self.barOffsetY = barOffsetY
        self.barWidthOffset = barWidthOffset
        self.barHeightOffset = barHeightOffset
        self.textScale = textScale
        self.textOffsetX = textOffsetX
        self.textOffsetY = textOffsetY
    }

    // Robuste Abwärtskompatibilität für alte gespeicherte JSONs
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.x = try container.decodeIfPresent(CGFloat.self, forKey: .x) ?? 0
        self.y = try container.decodeIfPresent(CGFloat.self, forKey: .y) ?? 0
        self.widthOffset = try container.decodeIfPresent(CGFloat.self, forKey: .widthOffset) ?? 0
        self.heightOffset = try container.decodeIfPresent(CGFloat.self, forKey: .heightOffset) ?? 0
        self.scale = try container.decodeIfPresent(CGFloat.self, forKey: .scale) ?? 1.0
        self.zIndex = try container.decodeIfPresent(Double.self, forKey: .zIndex) ?? 1.0
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true

        self.barScale = try container.decodeIfPresent(CGFloat.self, forKey: .barScale) ?? 1.0
        self.barOffsetX = try container.decodeIfPresent(CGFloat.self, forKey: .barOffsetX) ?? 0
        self.barOffsetY = try container.decodeIfPresent(CGFloat.self, forKey: .barOffsetY) ?? 0
        self.barWidthOffset = try container.decodeIfPresent(CGFloat.self, forKey: .barWidthOffset) ?? 0
        self.barHeightOffset = try container.decodeIfPresent(CGFloat.self, forKey: .barHeightOffset) ?? 0

        self.textScale = try container.decodeIfPresent(CGFloat.self, forKey: .textScale) ?? 1.0
        self.textOffsetX = try container.decodeIfPresent(CGFloat.self, forKey: .textOffsetX) ?? 0
        self.textOffsetY = try container.decodeIfPresent(CGFloat.self, forKey: .textOffsetY) ?? 0
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Studio Widget Catalog Definitionen
// ─────────────────────────────────────────────────────────────────────────────

public struct StudioWidgetDefinition: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let isLandscape: Bool

    public init(id: String, title: String, subtitle: String, icon: String, isLandscape: Bool) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isLandscape = isLandscape
    }
}

public final class HandyLayoutStudioManager: ObservableObject {
    public static let shared = HandyLayoutStudioManager()

    @AppStorage("carlyrics_studio_edit_mode") public var isEditModeActive: Bool = false
    @Published public var isScrollModeInStudio: Bool = false
    @Published public var selectedWidgetId: String? = nil
    @Published public var activeSubTarget: StudioEditSubTarget = .whole

    @Published public var portraitTransforms: [String: WidgetFreeformTransform] = [:]
    @Published public var landscapeTransforms: [String: WidgetFreeformTransform] = [:]
    @Published public var boostConfig: BoostWidgetConfig = BoostWidgetConfig()

    private let portraitStorageKey    = "carlyrics_studio_portrait_transforms_v4"
    private let landscapeStorageKey   = "carlyrics_studio_landscape_transforms_v4"
    private let boostConfigStorageKey = "carlyrics_studio_boost_config_v4"

    // Katalog aller verfügbaren Widgets
    public static let portraitWidgetsCatalog: [StudioWidgetDefinition] = [
        StudioWidgetDefinition(id: "w_lyrics", title: "Spotify Songtexte", subtitle: "Live Synchronisierte Lyrics", icon: "music.note.list", isLandscape: false),
        StudioWidgetDefinition(id: "w_gauges", title: "Haupt-Gauges (3er)", subtitle: "Öltemperatur, RPM Tacho & Ladedruck", icon: "gauge.with.needle.fill", isLandscape: false),
        StudioWidgetDefinition(id: "w_dyno", title: "Live Prüfstand (Dyno)", subtitle: "WinDyn V3.2 PS & Drehmoment Kurven", icon: "chart.xyaxis.line", isLandscape: false),
        StudioWidgetDefinition(id: "w_gforce", title: "G-Kräfte Radar", subtitle: "GBall Scope & Vektoren", icon: "scope", isLandscape: false),
        StudioWidgetDefinition(id: "w_stats", title: "Telemetrie Stats", subtitle: "8 Kacheln: IAT, MAF, Batterie etc.", icon: "square.grid.2x2.fill", isLandscape: false)
    ]

    public static let landscapeWidgetsCatalog: [StudioWidgetDefinition] = [
        StudioWidgetDefinition(id: "w_ls_left", title: "Links (Antrieb)", subtitle: "Ladedruck, Öltemp, IAT & GBall", icon: "engine.combustion.fill", isLandscape: true),
        StudioWidgetDefinition(id: "w_ls_center", title: "Mitte (Digital Tacho)", subtitle: "Zentraler Tacho mit Shift-Lights", icon: "gauge.with.dots.needle.bottom.50percent", isLandscape: true),
        StudioWidgetDefinition(id: "w_ls_right", title: "Rechts (Lyrics Console)", subtitle: "Album Cover & Songtexte", icon: "music.quarternote.3", isLandscape: true),
        StudioWidgetDefinition(id: "w_ls_bottom", title: "MoTeC Flight-Bar", subtitle: "Horizontales Telemetrie-Band", icon: "chart.bar.xaxis", isLandscape: true)
    ]

    public init() {
        loadData()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Transforms Access
    // ─────────────────────────────────────────────────────────────────────────

    public func transform(for id: String, isLandscape: Bool = false) -> WidgetFreeformTransform {
        if isLandscape {
            return landscapeTransforms[id] ?? WidgetFreeformTransform()
        } else {
            return portraitTransforms[id] ?? WidgetFreeformTransform()
        }
    }

    public func isWidgetVisible(id: String, isLandscape: Bool = false) -> Bool {
        transform(for: id, isLandscape: isLandscape).isVisible
    }

    public func setWidgetVisible(id: String, isLandscape: Bool = false, isVisible: Bool) {
        var current = transform(for: id, isLandscape: isLandscape)
        current.isVisible = isVisible
        apply(transform: current, for: id, isLandscape: isLandscape)
    }

    public func setPosition(id: String, isLandscape: Bool = false, x: CGFloat, y: CGFloat) {
        var current = transform(for: id, isLandscape: isLandscape)
        switch activeSubTarget {
        case .whole:
            current.x = x
            current.y = y
        case .bar:
            current.barOffsetX = x
            current.barOffsetY = y
        case .text:
            current.textOffsetX = x
            current.textOffsetY = y
        }
        apply(transform: current, for: id, isLandscape: isLandscape)
    }

    /// Präzisions-Nudge in einzelnen Koordinaten-Schritten (±1 pt)
    public func nudge(id: String, isLandscape: Bool = false, dx: CGFloat, dy: CGFloat) {
        var current = transform(for: id, isLandscape: isLandscape)
        switch activeSubTarget {
        case .whole:
            current.x += dx
            current.y += dy
        case .bar:
            current.barOffsetX += dx
            current.barOffsetY += dy
        case .text:
            current.textOffsetX += dx
            current.textOffsetY += dy
        }
        apply(transform: current, for: id, isLandscape: isLandscape)
    }

    public func setScale(id: String, isLandscape: Bool = false, scale: CGFloat) {
        var current = transform(for: id, isLandscape: isLandscape)
        let clamped = max(0.40, min(2.5, scale))
        switch activeSubTarget {
        case .whole:
            current.scale = clamped
        case .bar:
            current.barScale = clamped
        case .text:
            current.textScale = clamped
        }
        apply(transform: current, for: id, isLandscape: isLandscape)
    }

    public func stepScale(id: String, isLandscape: Bool = false, delta: CGFloat) {
        var current = transform(for: id, isLandscape: isLandscape)
        switch activeSubTarget {
        case .whole:
            current.scale = max(0.40, min(2.5, current.scale + delta))
        case .bar:
            current.barScale = max(0.40, min(2.5, current.barScale + delta))
        case .text:
            current.textScale = max(0.40, min(2.5, current.textScale + delta))
        }
        apply(transform: current, for: id, isLandscape: isLandscape)
    }

    public func resetSubTarget(id: String, isLandscape: Bool = false) {
        var current = transform(for: id, isLandscape: isLandscape)
        switch activeSubTarget {
        case .whole:
            current.x = 0
            current.y = 0
            current.scale = 1.0
            current.widthOffset = 0
            current.heightOffset = 0
        case .bar:
            current.barScale = 1.0
            current.barOffsetX = 0
            current.barOffsetY = 0
            current.barWidthOffset = 0
            current.barHeightOffset = 0
        case .text:
            current.textScale = 1.0
            current.textOffsetX = 0
            current.textOffsetY = 0
        }
        apply(transform: current, for: id, isLandscape: isLandscape)
    }

    public func resetWidget(id: String, isLandscape: Bool = false) {
        if isLandscape {
            landscapeTransforms.removeValue(forKey: id)
        } else {
            portraitTransforms.removeValue(forKey: id)
        }
        saveData()
    }

    public func resetAll(isLandscape: Bool = false) {
        if isLandscape {
            landscapeTransforms.removeAll()
            UserDefaults.standard.removeObject(forKey: landscapeStorageKey)
        } else {
            portraitTransforms.removeAll()
            UserDefaults.standard.removeObject(forKey: portraitStorageKey)
        }
        selectedWidgetId = nil
    }

    public func updateBoostConfig(_ update: (inout BoostWidgetConfig) -> Void) {
        update(&boostConfig)
        if let data = try? JSONEncoder().encode(boostConfig) {
            UserDefaults.standard.set(data, forKey: boostConfigStorageKey)
        }
    }

    private func apply(transform: WidgetFreeformTransform, for id: String, isLandscape: Bool) {
        if isLandscape {
            landscapeTransforms[id] = transform
        } else {
            portraitTransforms[id] = transform
        }
        saveData()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Persistence & Export
    // ─────────────────────────────────────────────────────────────────────────

    private func saveData() {
        if let pData = try? JSONEncoder().encode(portraitTransforms) {
            UserDefaults.standard.set(pData, forKey: portraitStorageKey)
        }
        if let lData = try? JSONEncoder().encode(landscapeTransforms) {
            UserDefaults.standard.set(lData, forKey: landscapeStorageKey)
        }
        if let bData = try? JSONEncoder().encode(boostConfig) {
            UserDefaults.standard.set(bData, forKey: boostConfigStorageKey)
        }
    }

    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: portraitStorageKey),
           let decoded = try? JSONDecoder().decode([String: WidgetFreeformTransform].self, from: data) {
            self.portraitTransforms = decoded
        }
        if let data = UserDefaults.standard.data(forKey: landscapeStorageKey),
           let decoded = try? JSONDecoder().decode([String: WidgetFreeformTransform].self, from: data) {
            self.landscapeTransforms = decoded
        }
        if let data = UserDefaults.standard.data(forKey: boostConfigStorageKey),
           let decoded = try? JSONDecoder().decode(BoostWidgetConfig.self, from: data) {
            self.boostConfig = decoded
        }
    }

    public func exportJSON() -> String {
        let export: [String: Any] = [
            "version": 4,
            "portrait": portraitTransforms.mapValues { [
                "x": $0.x, "y": $0.y,
                "scale": $0.scale,
                "isVisible": $0.isVisible,
                "barScale": $0.barScale,
                "barOffsetX": $0.barOffsetX,
                "barOffsetY": $0.barOffsetY,
                "textScale": $0.textScale,
                "textOffsetX": $0.textOffsetX,
                "textOffsetY": $0.textOffsetY
            ] },
            "landscape": landscapeTransforms.mapValues { [
                "x": $0.x, "y": $0.y,
                "scale": $0.scale,
                "isVisible": $0.isVisible,
                "barScale": $0.barScale,
                "barOffsetX": $0.barOffsetX,
                "barOffsetY": $0.barOffsetY,
                "textScale": $0.textScale,
                "textOffsetX": $0.textOffsetX,
                "textOffsetY": $0.textOffsetY
            ] }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: View Modifiers für Balken & Text Verziehen
// ─────────────────────────────────────────────────────────────────────────────

public struct StudioBarTransformModifier: ViewModifier {
    public let id: String
    public var isLandscape: Bool = false
    @ObservedObject private var studio = HandyLayoutStudioManager.shared

    public func body(content: Content) -> some View {
        let t = studio.transform(for: id, isLandscape: isLandscape)
        content
            .scaleEffect(t.barScale)
            .offset(x: t.barOffsetX, y: t.barOffsetY)
    }
}

public struct StudioTextTransformModifier: ViewModifier {
    public let id: String
    public var isLandscape: Bool = false
    @ObservedObject private var studio = HandyLayoutStudioManager.shared

    public func body(content: Content) -> some View {
        let t = studio.transform(for: id, isLandscape: isLandscape)
        content
            .scaleEffect(t.textScale)
            .offset(x: t.textOffsetX, y: t.textOffsetY)
    }
}

extension View {
    public func studioBar(id: String, isLandscape: Bool = false) -> some View {
        self.modifier(StudioBarTransformModifier(id: id, isLandscape: isLandscape))
    }

    public func studioText(id: String, isLandscape: Bool = false) -> some View {
        self.modifier(StudioTextTransformModifier(id: id, isLandscape: isLandscape))
    }
}
