// MARK: - CarLyricsWidgetBundle.swift
// CarLyrics Widget Extension – Entry Point
// ─────────────────────────────────────────────────────────────────────────────
// Target membership: CarLyricsWidgetExtension ONLY
// ─────────────────────────────────────────────────────────────────────────────

import WidgetKit
import SwiftUI

@main
struct CarLyricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Live Activity & Dynamic Island Widget
        LyricsActivityWidget()

        // Modular Split Widgets (Lock Screen, Home Screen, StandBy)
        OilTempWidget()
        GForceWidget()
        BoostPerformanceWidget()
        LyricsWidget()
        TelemetryCockpitWidget()
    }
}
