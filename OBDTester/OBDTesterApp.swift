// MARK: - OBDTesterApp.swift
// Eigenständige Standalone-App zur Fahrzeugdiagnose & ELM327 Protokoll-Analyse.
// Speziell für VW EA113 2.0 TFSI (Bosch MED9.1) & ELM327 Bluetooth Adapter.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

@main
struct OBDTesterApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    OBDManager.shared.enableOBD()
                }
        }
    }
}
