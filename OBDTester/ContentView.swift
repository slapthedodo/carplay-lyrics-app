// MARK: - ContentView.swift (OBD Tester Standalone Edition)
// Vollständige Diagnose- & Protokoll-Werkbank mit Tausenden Methoden für Bosch MED9.1.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

struct ContentView: View {
    @ObservedObject private var obd = OBDManager.shared

    var body: some View {
        OBDDiagnosticWorkbenchView(obd: obd, isPresentedAsSheet: false)
    }
}
