// MARK: - HandyLayoutStudioManager.swift
// Freies 2D Studio-Layout-System für das Handy-Cockpit (Portrait & Landscape)
// Ermöglicht freies Verschieben (X, Y), Skalieren, Resizen, Nudge D-Pad und JSON Export
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct WidgetFreeformTransform: Codable, Equatable {
    public var x: CGFloat = 0
    public var y: CGFloat = 0
    public var widthOffset: CGFloat = 0
    public var heightOffset: CGFloat = 0
    public var scale: CGFloat = 1.0
    public var zIndex: Double = 1.0

    public init(
        x: CGFloat = 0,
        y: CGFloat = 0,
        widthOffset: CGFloat = 0,
        heightOffset: CGFloat = 0,
        scale: CGFloat = 1.0,
        zIndex: Double = 1.0
    ) {
        self.x = x
        self.y = y
        self.widthOffset = widthOffset
        self.heightOffset = heightOffset
        self.scale = scale
        self.zIndex = zIndex
    }
}

public final class HandyLayoutStudioManager: ObservableObject {
    public static let shared = HandyLayoutStudioManager()

    @AppStorage("carlyrics_studio_edit_mode") public var isEditModeActive: Bool = false
    @Published public var isScrollModeInStudio: Bool = false
    @Published public var selectedWidgetId: String? = nil

    @Published public var portraitTransforms: [String: WidgetFreeformTransform] = [:]
    @Published public var landscapeTransforms: [String: WidgetFreeformTransform] = [:]
    @Published public var boostConfig: BoostWidgetConfig = BoostWidgetConfig()

    private let portraitStorageKey  = "carlyrics_studio_portrait_transforms_v3"
    private let landscapeStorageKey = "carlyrics_studio_landscape_transforms_v3"
    private let boostConfigStorageKey = "carlyrics_studio_boost_config_v3"

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

    public func setPosition(id: String, isLandscape: Bool = false, x: CGFloat, y: CGFloat) {
        var current = transform(for: id, isLandscape: isLandscape)
        current.x = x
        current.y = y
        apply(transform: current, for: id, isLandscape: isLandscape)
    }

    public func nudge(id: String, isLandscape: Bool = false, dx: CGFloat, dy: CGFloat) {
        var current = transform(for: id, isLandscape: isLandscape)
        current.x += dx
        current.y += dy
        apply(transform: current, for: id, isLandscape: isLandscape)
    }

    public func setScale(id: String, isLandscape: Bool = false, scale: CGFloat) {
        var current = transform(for: id, isLandscape: isLandscape)
        current.scale = max(0.50, min(2.0, scale))
        apply(transform: current, for: id, isLandscape: isLandscape)
    }

    public func setSize(id: String, isLandscape: Bool = false, widthOffset: CGFloat, heightOffset: CGFloat) {
        var current = transform(for: id, isLandscape: isLandscape)
        current.widthOffset = widthOffset
        current.heightOffset = heightOffset
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
            "version": 3,
            "boostConfig": [
                "orientation": boostConfig.orientation.rawValue,
                "thickness": boostConfig.thickness.rawValue,
                "showNumeric": boostConfig.showNumeric,
                "showPeak": boostConfig.showPeak
            ],
            "portrait": portraitTransforms.mapValues { [
                "x": $0.x, "y": $0.y,
                "widthOffset": $0.widthOffset, "heightOffset": $0.heightOffset,
                "scale": $0.scale
            ] },
            "landscape": landscapeTransforms.mapValues { [
                "x": $0.x, "y": $0.y,
                "widthOffset": $0.widthOffset, "heightOffset": $0.heightOffset,
                "scale": $0.scale
            ] }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}
