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

        // Home Screen & Lock Screen Widgets (Small, Medium, Circular, Rectangular, Inline)
        TelemetryCockpitWidget()
    }
}
