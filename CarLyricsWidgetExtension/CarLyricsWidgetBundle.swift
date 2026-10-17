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

        // ── Die 3 Wunsch-Kacheln für CarPlay & Homescreen ──
        TelemetryCockpitWidget()    // Kachel 1 (Links):  Thermik (Öl & Wasser) + G-Kraft Scope (20% größer) + Peak
        BoostPerformanceWidget()    // Kachel 2 (Mitte):  Turbo Ladedruck (Bar-Balken) + Ansaug (IAT) & Masse (MAF) Kugeln
        LyricsWidget()              // Kachel 3 (Rechts): Live-Songtext 5 Zeilen (Queen / Spotify) + Zeiten am Fortschrittsbalken

        // Optionale Einzelfokus-Widgets:
        OilTempWidget()             // Reine Öltemperatur-Scheibe
        GForceWidget()              // Reines G-Kraft Rundinstrument
    }
}
