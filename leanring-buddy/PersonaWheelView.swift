//
//  PersonaWheelView.swift
//  leanring-buddy
//
//  Radial picker that appears around the cursor while the persona-wheel
//  hotkey (shift + cmd) is held. The user moves the cursor toward one
//  of the spokes, then releases the modifier to commit. Releasing while
//  the cursor is still inside the dead-zone in the middle leaves the
//  current persona unchanged.
//
//  The wheel is rendered inside the existing OverlayWindow (one per
//  screen) as a child of BlueCursorView. Geometry: spokes are laid out
//  on a 110pt-radius circle around the wheel's center point, starting
//  at 12 o'clock and going clockwise. Each spoke is a 56pt circular
//  PersonaAvatarView. The currently-hovered spoke gets a scale-up and a
//  white ring, plus a name label rendered just outside the ring.
//

import SwiftUI

struct PersonaWheelView: View {
    /// All personas to render around the wheel — usually
    /// `PersonaStore.allWheelPersonas` (Me, Team, then teammates).
    let personas: [PersonaBundle]

    /// Id of the persona currently being hovered toward, or nil when
    /// the cursor is in the dead-zone in the middle. Updated by the
    /// parent (BlueCursorView) every frame as the cursor moves.
    let hoveredPersonaId: String?

    /// Id of the persona that's currently active (e.g. the one Sticky
    /// is wearing right now). Drawn with a subtle "currently selected"
    /// indicator so the user can tell which spoke is the no-op release.
    let activePersonaId: String

    // MARK: - Geometry constants

    /// Distance from the wheel's center point to each spoke's center.
    /// Tuned so a 56pt avatar at this radius doesn't overlap the cursor
    /// orb (which sits at the center) but is still close enough to
    /// reach with a small wrist movement.
    static let spokeRadius: CGFloat = 110

    /// Diameter of each spoke avatar. Bigger than the panel picker
    /// avatar so they're readable at arm's length.
    static let spokeDiameter: CGFloat = 56

    /// The wheel's overall canvas size — large enough to contain every
    /// spoke (radius + half a spoke diameter) plus padding for the
    /// hover ring and the name label that pops out when a spoke is
    /// hovered. Used to size the SwiftUI hit area.
    static let wheelCanvasSize: CGFloat = (spokeRadius + spokeDiameter) * 2 + 80

    var body: some View {
        ZStack {
            wheelBackgroundDimmer
            ForEach(Array(personas.enumerated()), id: \.element.id) { index, persona in
                spokeView(for: persona, atIndex: index)
            }
        }
        .frame(width: Self.wheelCanvasSize, height: Self.wheelCanvasSize)
        .allowsHitTesting(false) // selection happens via cursor-position polling, not taps
    }

    // MARK: - Background dimmer

    /// Soft circular wash behind the spokes so the wheel reads as a
    /// distinct surface against busy desktop wallpapers. Kept very
    /// subtle — the spokes themselves are the figure; this is just
    /// enough ground to ground them on.
    private var wheelBackgroundDimmer: some View {
        Circle()
            .fill(Color.black.opacity(0.18))
            .frame(width: Self.spokeRadius * 2 + Self.spokeDiameter + 24,
                   height: Self.spokeRadius * 2 + Self.spokeDiameter + 24)
            .blur(radius: 24)
    }

    // MARK: - Spoke rendering

    /// Renders a single spoke at its angular position. The hovered
    /// spoke gets a scale-up, a white ring, and an inline name label
    /// rendered just above the avatar (or below, if the spoke is in
    /// the upper half — we want the label to push outward from the
    /// wheel center, not toward it).
    private func spokeView(for persona: PersonaBundle, atIndex spokeIndex: Int) -> some View {
        let angleInRadians = angleForSpoke(atIndex: spokeIndex, totalSpokes: personas.count)
        let spokeOffsetX = cos(angleInRadians) * Self.spokeRadius
        let spokeOffsetY = sin(angleInRadians) * Self.spokeRadius

        let isHovered = (persona.id == hoveredPersonaId)
        let isActive = (persona.id == activePersonaId)

        return ZStack {
            PersonaAvatarView(
                avatar: persona.avatar,
                diameter: Self.spokeDiameter,
                showsRing: isHovered || isActive,
                ringColor: isHovered ? Color.white : Color.white.opacity(0.45),
                ringLineWidth: isHovered ? 3.0 : 1.5
            )
            .scaleEffect(isHovered ? 1.18 : 1.0)
            .shadow(
                color: persona.accentColor.opacity(isHovered ? 0.85 : 0.45),
                radius: isHovered ? 18 : 8
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)

            if isHovered {
                spokeNameLabel(for: persona, atAngle: angleInRadians)
            }
        }
        .offset(x: spokeOffsetX, y: spokeOffsetY)
    }

    /// Computes the angular position (in radians, 0 = 3 o'clock,
    /// negative-pi/2 = 12 o'clock) for a spoke at the given index in a
    /// wheel of `totalSpokes` total. Starts at 12 and goes clockwise so
    /// the first persona (Me) sits at the top — the most predictable
    /// "default" position for a quick wrist flick to land on.
    private func angleForSpoke(atIndex spokeIndex: Int, totalSpokes: Int) -> CGFloat {
        guard totalSpokes > 0 else { return 0 }
        let degreesPerSpoke = 360.0 / CGFloat(totalSpokes)
        let degrees = -90.0 + degreesPerSpoke * CGFloat(spokeIndex)
        return degrees * .pi / 180.0
    }

    /// Name + role label rendered next to the hovered spoke. Positioned
    /// outward from the wheel center so it doesn't overlap the cursor /
    /// other spokes. Pinned-text rather than a floating tooltip so it
    /// doesn't lag the spoke during hover transitions.
    private func spokeNameLabel(for persona: PersonaBundle, atAngle angleInRadians: CGFloat) -> some View {
        let labelOffsetMagnitude = Self.spokeDiameter / 2 + 28
        let labelOffsetX = cos(angleInRadians) * labelOffsetMagnitude
        let labelOffsetY = sin(angleInRadians) * labelOffsetMagnitude

        return VStack(spacing: 2) {
            Text(persona.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            if let role = persona.role, !role.isEmpty {
                Text(role)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(persona.accentColor.opacity(0.6), lineWidth: 1)
        )
        .fixedSize()
        .offset(x: labelOffsetX, y: labelOffsetY)
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
    }
}

// MARK: - Geometry helpers usable by the parent (cursor-position → spoke index)

enum PersonaWheelGeometry {
    /// Distance below which the cursor is considered to be in the
    /// dead-zone (no spoke hovered). Slightly larger than half the
    /// spoke radius so casual jitter near the center doesn't keep
    /// flipping which spoke is highlighted.
    static let deadZoneRadius: CGFloat = 28

    /// Picks the spoke index that the given cursor offset (relative
    /// to the wheel center, in SwiftUI coordinate space — y grows
    /// downward) is currently pointing toward. Returns nil when the
    /// cursor is inside the dead zone. The returned index can be used
    /// to look up the persona in the same array passed to the wheel.
    static func hoveredSpokeIndex(
        cursorOffsetFromCenter: CGPoint,
        totalSpokes: Int
    ) -> Int? {
        guard totalSpokes > 0 else { return nil }

        let cursorDistanceFromCenter = sqrt(
            cursorOffsetFromCenter.x * cursorOffsetFromCenter.x +
            cursorOffsetFromCenter.y * cursorOffsetFromCenter.y
        )
        guard cursorDistanceFromCenter > deadZoneRadius else { return nil }

        // atan2 returns radians where 0 = +x axis (3 o'clock) and
        // y grows downward in SwiftUI, so positive angles sweep
        // clockwise — exactly the same convention as the spoke layout.
        let cursorAngleInRadians = atan2(cursorOffsetFromCenter.y, cursorOffsetFromCenter.x)
        let cursorAngleInDegrees = cursorAngleInRadians * 180.0 / .pi

        // Shift so 12 o'clock (where spoke 0 lives) maps to 0 degrees,
        // then normalize into [0, 360). Each spoke covers (360 /
        // totalSpokes) degrees centered on its midline, so dividing
        // by that step and rounding to the nearest int picks the
        // hovered spoke.
        let degreesShifted = cursorAngleInDegrees + 90
        let degreesNormalized = (degreesShifted.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)

        let degreesPerSpoke = 360.0 / CGFloat(totalSpokes)
        let nearestSpokeIndex = Int((degreesNormalized / degreesPerSpoke).rounded()) % totalSpokes

        return nearestSpokeIndex
    }
}
