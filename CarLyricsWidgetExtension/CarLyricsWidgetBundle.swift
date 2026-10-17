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
        // 1. Live Activity & Dynamic Island (Sperrbildschirm Banner mit allen 5 Kugeln & Songtext)
        LyricsActivityWidget()

        // 2. Das eine echte Cockpit Widget (Small 2x2, Medium 2x4, Sperrbildschirm)
        TelemetryCockpitWidget()
    }
}
