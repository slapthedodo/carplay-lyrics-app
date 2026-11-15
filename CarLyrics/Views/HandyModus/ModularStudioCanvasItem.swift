// MARK: - ModularStudioCanvasItem.swift
// Universeller Studio-Wrapper für jedes Widget im Handy-Cockpit
// Ermöglicht verzögerungsfreies Draggen auf ersten Touch, Corner-Resizing & Nudging,
// Sub-Target Steuerung (Gesamt/Balken/Text) und 1-Click Widget-Entfernung
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
        if !currentTransform.isVisible {
            EmptyView()
        } else {
            canvasItemContent
        }
    }

    private var canvasItemContent: some View {
        let isEditing = studio.isEditModeActive && !studio.isScrollModeInStudio

        // Berechne aktive Offsets je nach SubTarget
        let activeX: CGFloat = {
            if isEditing && isSelected && studio.activeSubTarget == .whole {
                return currentTransform.x + dragCurrentOffset.width
            }
            return currentTransform.x
        }()

        let activeY: CGFloat = {
            if isEditing && isSelected && studio.activeSubTarget == .whole {
                return currentTransform.y + dragCurrentOffset.height
            }
            return currentTransform.y
        }()

        let activeScale: CGFloat = {
            if isEditing && isSelected && studio.activeSubTarget == .whole {
                return max(0.40, min(2.5, currentTransform.scale + scaleCurrentDelta))
            }
            return currentTransform.scale
        }()

        return ZStack(alignment: .bottomTrailing) {
            // ── Widget Inhalt ─────────────────────────────────────────────────
            content()
                .scaleEffect(activeScale)

            // ── Studio Interaktions-Overlay (nur im Edit-Modus) ───────────────
            if isEditing {
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
                                applyDragEnded(translation: val.translation)
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
                        isSelected ? Color.cyan : Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1, dash: isSelected ? [] : [6, 4])
                    )
                    .shadow(color: isSelected ? Color.cyan.opacity(0.8) : .clear, radius: 10)
                    .allowsHitTesting(false)

                // ── Header-Badge bei Selektion (Titel + SubTarget Switcher + Löschen) ──
                if isSelected {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            // Titel Badge
                            HStack(spacing: 3) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.system(size: 8, weight: .black))
                                Text(title)
                                    .font(.system(size: 9.5, weight: .black, design: .rounded))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.cyan, in: Capsule())

                            // Sub-Target Switcher (Gesamt | Balken | Text)
                            HStack(spacing: 2) {
                                ForEach(StudioEditSubTarget.allCases) { sub in
                                    Button {
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                            studio.activeSubTarget = sub
                                        }
                                    } label: {
                                        Text(sub.rawValue)
                                            .font(.system(size: 8, weight: studio.activeSubTarget == sub ? .black : .bold))
                                            .foregroundStyle(studio.activeSubTarget == sub ? .black : .white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2.5)
                                            .background(
                                                studio.activeSubTarget == sub ? Color.white : Color.white.opacity(0.12),
                                                in: Capsule()
                                            )
                                    }
                                }
                            }
                            .padding(2)
                            .background(Color.black.opacity(0.8), in: Capsule())

                            Spacer()

                            // Schnell-Reset
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    studio.resetSubTarget(id: id, isLandscape: isLandscape)
                                    dragCurrentOffset = .zero
                                    scaleCurrentDelta = 0.0
                                }
                            } label: {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.orange)
                                    .background(Color.black, in: Circle())
                            }

                            // Widget Entfernen
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    studio.setWidgetVisible(id: id, isLandscape: isLandscape, isVisible: false)
                                    studio.selectedWidgetId = nil
                                }
                            } label: {
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.red)
                                    .background(Color.black, in: Circle())
                            }
                        }
                        .offset(x: 4, y: -14)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    // ── Fließender Resize / Scale Griff unten rechts ───────────
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(.black)
                        )
                        .shadow(color: Color.cyan.opacity(0.9), radius: 8)
                        .offset(x: 10, y: 10)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    let delta = (val.translation.width + val.translation.height) / 220.0
                                    scaleCurrentDelta = delta
                                }
                                .onEnded { val in
                                    let delta = (val.translation.width + val.translation.height) / 220.0
                                    applyScaleEnded(delta: delta)
                                    scaleCurrentDelta = 0.0
                                }
                        )
                }
            }
        }
        .offset(x: activeX, y: activeY)
        .zIndex(isSelected ? 999 : currentTransform.zIndex)
    }

    private func applyDragEnded(translation: CGSize) {
        var t = currentTransform
        switch studio.activeSubTarget {
        case .whole:
            t.x += translation.width
            t.y += translation.height
        case .bar:
            t.barOffsetX += translation.width
            t.barOffsetY += translation.height
        case .text:
            t.textOffsetX += translation.width
            t.textOffsetY += translation.height
        }
        studio.setPosition(
            id: id,
            isLandscape: isLandscape,
            x: studio.activeSubTarget == .whole ? t.x : (studio.activeSubTarget == .bar ? t.barOffsetX : t.textOffsetX),
            y: studio.activeSubTarget == .whole ? t.y : (studio.activeSubTarget == .bar ? t.barOffsetY : t.textOffsetY)
        )
    }

    private func applyScaleEnded(delta: CGFloat) {
        switch studio.activeSubTarget {
        case .whole:
            let newScale = max(0.40, min(2.5, currentTransform.scale + delta))
            studio.setScale(id: id, isLandscape: isLandscape, scale: newScale)
        case .bar:
            let newScale = max(0.40, min(2.5, currentTransform.barScale + delta))
            var t = currentTransform
            t.barScale = newScale
            studio.setScale(id: id, isLandscape: isLandscape, scale: newScale)
        case .text:
            let newScale = max(0.40, min(2.5, currentTransform.textScale + delta))
            var t = currentTransform
            t.textScale = newScale
            studio.setScale(id: id, isLandscape: isLandscape, scale: newScale)
        }
    }
}
