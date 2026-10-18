// MARK: - HandyModusBackground.swift
// Racing-Hintergrund: Carbon-Fiber-Textur + dynamische Scan-Linie
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Carbon-Fiber Canvas Pattern
// ─────────────────────────────────────────────────────────────────────────────

struct CarbonFiberBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            Canvas { ctx, size in
                let tileSize: CGFloat = 12
                let cols = Int(size.width  / tileSize) + 2
                let rows = Int(size.height / tileSize) + 2

                for row in 0..<rows {
                    for col in 0..<cols {
                        let x = CGFloat(col) * tileSize
                        let y = CGFloat(row) * tileSize
                        let isEven = (row + col) % 2 == 0

                        // Woven warp thread
                        var warpRect = CGRect(x: x, y: y, width: tileSize - 1, height: tileSize - 1)
                        var path = Path(warpRect)
                        ctx.fill(path, with: .color(.white.opacity(isEven ? 0.025 : 0.01)))

                        // Highlight edge — weave shimmer
                        let shimmer = isEven ? CGRect(x: x, y: y, width: tileSize - 1, height: 1.5)
                                             : CGRect(x: x, y: y + tileSize - 2.5, width: tileSize - 1, height: 1.5)
                        warpRect = shimmer
                        path = Path(warpRect)
                        ctx.fill(path, with: .color(.white.opacity(isEven ? 0.045 : 0.02)))
                    }
                }
            }
            .ignoresSafeArea()

            // Deep central vignette
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.6)],
                center: .center,
                startRadius: 100,
                endRadius: 450
            )
            .ignoresSafeArea()

            // Subtle cyan glow top
            RadialGradient(
                colors: [Color.cyan.opacity(0.07), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 350
            )
            .ignoresSafeArea()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Scan Line Overlay
// ─────────────────────────────────────────────────────────────────────────────

struct ScanLineOverlay: View {
    @State private var offset: CGFloat = -UIScreen.main.bounds.height

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.cyan.opacity(0.12), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 60)
                .offset(y: offset)
                .onAppear {
                    withAnimation(
                        .linear(duration: 4.5)
                        .repeatForever(autoreverses: false)
                    ) {
                        offset = geo.size.height + 60
                    }
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Full Dashboard Background
// ─────────────────────────────────────────────────────────────────────────────

public struct HandyModusBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            CarbonFiberBackground()
            ScanLineOverlay()
        }
    }
}
