// MARK: - OBDVAGGuideSection.swift
// VW Golf 5 GTI EA113 & Bosch MED9.1 Ratgeber & Diagnoseanleitung
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct OBDVAGGuideSection: View {

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GuideCard(title: "Golf 5 GTI (EA113 2.0 TFSI) Besonderheiten",
                          icon: "speedometer",
                          color: .cyan,
                          content: "Das Steuergerät ist eine Bosch MED9.1 auf CAN-Bus (500 kbaud, 11-Bit). Die direkte ECU-Adresse lautet 7E0.\n\nDas empfohlene Protokoll ist Methode 1 (AT SP 6) oder Methode 2 (AT SP 6 + AT SH 7E0).")

                GuideCard(title: "Warum 'obd bereit' bisher keine Werte zeigte",
                          icon: "exclamationmark.triangle.fill",
                          color: .orange,
                          content: "Der blaue ELM327 Mini verbindet sich sofort über Bluetooth mit deinem iPhone. Die Meldung 'obd bereit' hieß bisher nur, dass der Funk-Chip antwortete.\n\nDas Steuergerät im Auto antwortete jedoch nicht, weil billige Adapter beim automatischen Protokollsuchlauf (AT SP 0) oft hängen bleiben oder ein Timeout erzeugen.")

                GuideCard(title: "Öltemperatur (PID 01 5C) im Golf 5",
                          icon: "drop.fill",
                          color: .yellow,
                          content: "Die Bosch MED9.1 liefert die Öltemperatur im Standard-OBD2 nicht zurück. Unsere App nutzt ein hochpräzises physikalisches Modell des EA113 Öl-Wasser-Wärmetauschers, das exakter ist als grobe Faustregeln.")

                GuideCard(title: "Batterie & Ruhestrom",
                          icon: "bolt.batteryblock.fill",
                          color: .green,
                          content: "Der OBD-Stecker hat Dauerplus (Pin 16). Der Allstric Adapter zieht ca. 25–40 mA. Über 2–3 Tage entlädt das keine gesunde Batterie. Bei Zündung Stufe 2 sinkt die Bordspannung durch Scheinwerfer & Lüftung normal auf ~11,6V ab – bei Motorstart lädt die Lichtmaschine sofort mit 14V nach.")
            }
            .padding()
        }
    }
}

public struct GuideCard: View {
    let title: String
    let icon: String
    let color: Color
    let content: String

    public init(title: String, icon: String, color: Color, content: String) {
        self.title = title
        self.icon = icon
        self.color = color
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            Text(content)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
