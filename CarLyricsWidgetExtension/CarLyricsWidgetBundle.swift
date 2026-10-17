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
        // The Live Activity widget
        LyricsActivityWidget()
        // Add future home-screen widgets here, e.g.:
        // LyricsNowPlayingWidget()
    }
}
