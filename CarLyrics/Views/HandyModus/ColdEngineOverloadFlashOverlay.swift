// MARK: - ColdEngineOverloadFlashOverlay.swift
// Kaltstart-Überlastung Warn-Overlay (Rot blinkend) für den Schutz des Motors
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct ColdEngineOverloadFlashOverlay: View {
    public let title: String
    public let detail: String
    @State private var isBlinking = false

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Rot blinkende Rand-Vignette
            Rectangle()
                .strokeBorder(Color.red.opacity(isBlinking ? 0.95 : 0.25), lineWidth: 10)
                .background(Color.red.opacity(isBlinking ? 0.20 : 0.04))
                .ignoresSafeArea()

            // Alarm-Banner oben
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isBlinking)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                }
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.red.opacity(0.95))
                    .shadow(color: .red.opacity(0.8), radius: 20)
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                isBlinking = true
            }
        }
    }
}
