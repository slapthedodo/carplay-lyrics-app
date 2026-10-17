// MARK: - OBDTesterApp.swift
// Eigenständige Standalone-App zur Fahrzeugdiagnose & ELM327 Protokoll-Analyse.
// Speziell für VW EA113 2.0 TFSI (Bosch MED9.1) & ELM327 Bluetooth Adapter.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

@main
struct OBDTesterApp: App {

    init() {
        // Direkt beim App-Start Bluetooth-Scan & OBD aktivieren
        OBDManager.shared.enableOBD()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
