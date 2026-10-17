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
        // Live Activity & Dynamic Island (für Sperrbildschirm mit allen 5 Kugeln)
        LyricsActivityWidget()

        // Die 5 Kacheln für deine 3 Slots:
        TelemetryCockpitWidget()    // 1. All-in-One Cockpit (TFSI 2.0 in Türkis + Scheibe + Boost + Peak)
        OilTempWidget()             // 2. Reine Öltemperatur-Scheibe (Groß, mit Thermometer & Ring)
        BoostPerformanceWidget()    // 3. Reiner Turbo Ladedruck (BAR BOOST, IAT, MAF)
        GForceWidget()              // 4. Reines G-Kraft Fadenkreuz (Lila Scope, Live-G & Peak)
        LyricsWidget()              // 5. Reiner Live-Songtext (Spotify synchronisiert)
    }
}
