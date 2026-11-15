// MARK: - ModularStudioCanvasItem.swift
// Universeller Studio-Wrapper für jedes Widget im Handy-Cockpit
// Ermöglicht verzögerungsfreies Draggen auf ersten Touch, Corner-Resizing & Nudging
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

public struct ModularStudioCanvasItem<Content: View>: View {
    public let id: String
    public let title: String
    public var isLandscape: Bool = false
    @ObservedObject private var studio = HandyLayoutStudioManager.shared
    @ViewBuilder public let content: () -> Content

    @State private var dragCurrentOffset: CGSize = .zero
    @State private var scaleCurrentDelta: CGFloat = 0.0

    public init(
        id: String,
        title: String,
        isLandscape: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.id = id
        self.title = title
        self.isLandscape = isLandscape
        self.content = content
    }

    private var isSelected: Bool {
        studio.selectedWidgetId == id
    }

    private var currentTransform: WidgetFreeformTransform {
        studio.transform(for: id, isLandscape: isLandscape)
    }

    public var body: some View {
        let activeX = currentTransform.x + dragCurrentOffset.width
        let activeY = currentTransform.y + dragCurrentOffset.height
        let activeScale = max(0.50, min(2.0, currentTransform.scale + scaleCurrentDelta))

        ZStack(alignment: .bottomTrailing) {
            // ── Widget Inhalt ─────────────────────────────────────────────────
            content()
                .scaleEffect(activeScale)

            // ── Studio Interaktions-Overlay (nur im Edit-Modus) ───────────────
            if studio.isEditModeActive && !studio.isScrollModeInStudio {
                // Unsichtbare Fangschicht über der gesamten Kachel:
                // Nimmt SOFORT beim ersten Touch die Auswahl und beginnt zu draggen!
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { val in
                                if studio.selectedWidgetId != id {
                                    studio.selectedWidgetId = id
                                }
                                dragCurrentOffset = val.translation
                            }
                            .onEnded { val in
                                studio.setPosition(
                                    id: id,
                                    isLandscape: isLandscape,
                                    x: currentTransform.x + val.translation.width,
                                    y: currentTransform.y + val.translation.height
                                )
                                dragCurrentOffset = .zero
                            }
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            studio.selectedWidgetId = (studio.selectedWidgetId == id) ? nil : id
                        }
                    }

                // Rahmen & Selektions-Visuals
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isSelected ? Color.cyan : Color.white.opacity(0.20),
                        style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1, dash: isSelected ? [] : [6, 4])
                    )
                    .shadow(color: isSelected ? Color.cyan.opacity(0.8) : .clear, radius: 10)
                    .allowsHitTesting(false)

                // ── Header-Badge bei Selektion (Titel + Koordinaten + Reset) ───
                if isSelected {
                    VStack(alignment: .leading) {
                        HStack(spacing: 5) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .font(.system(size: 8, weight: .black))
                                Text(title)
                                    .font(.system(size: 9.5, weight: .black, design: .rounded))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.cyan, in: Capsule())

                            Text("X:\(Int(activeX)) Y:\(Int(activeY)) • \(Int(round(activeScale * 100)))%")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.85), in: Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8))

                            Spacer()

                            // Schnell-Reset Knopf für dieses Widget
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    studio.resetWidget(id: id, isLandscape: isLandscape)
                                    dragCurrentOffset = .zero
                                    scaleCurrentDelta = 0.0
                                }
                            } label: {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.orange)
                                    .background(Color.black, in: Circle())
                            }
                        }
                        .offset(x: 4, y: -12)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    // ── Fließender Resize / Scale Griff unten rechts ───────────
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.black)
                        )
                        .shadow(color: Color.cyan.opacity(0.9), radius: 8)
                        .offset(x: 8, y: 8)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    let delta = (val.translation.width + val.translation.height) / 220.0
                                    scaleCurrentDelta = delta
                                }
                                .onEnded { val in
                                    let delta = (val.translation.width + val.translation.height) / 220.0
                                    let newScale = max(0.50, min(2.0, currentTransform.scale + delta))
                                    studio.setScale(id: id, isLandscape: isLandscape, scale: newScale)
                                    scaleCurrentDelta = 0.0
                                }
                        )
                }
            }
        }
        .offset(x: activeX, y: activeY)
        .zIndex(isSelected ? 999 : currentTransform.zIndex)
    }
}
