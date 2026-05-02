//
//  PersonaWheelHotkeyMonitor.swift
//  leanring-buddy
//
//  Hold-to-show shortcut for the radial persona picker. Distinct from
//  the push-to-talk shortcut (ctrl + option) so the user can summon the
//  wheel without entering a voice session. Uses the same listen-only
//  CGEvent tap pattern as GlobalPushToTalkShortcutMonitor — modifier-
//  only detection via .flagsChanged so no key has to be tapped to
//  commit, just held.
//
//  Default combo: shift + cmd held together. Two modifiers makes it
//  clearly intentional (no accidental triggers from cmd-tap or shift-
//  tap during normal typing) and doesn't collide with system hotkeys
//  the way cmd + option does.
//

import AppKit
import Combine
import CoreGraphics
import Foundation

final class PersonaWheelHotkeyMonitor: ObservableObject {
    /// Fires `.pressed` when the hotkey is first held and `.released`
    /// when it's let go. Subscribers (CompanionManager) flip the wheel
    /// overlay's `isVisible` flag in response.
    let hotkeyTransitionPublisher = PassthroughSubject<HotkeyTransition, Never>()

    enum HotkeyTransition {
        case pressed
        case released
    }

    /// The modifier combo that summons the wheel. Held-only, no key
    /// press required — releasing any modifier in the combo ends the
    /// session and commits the currently-hovered persona.
    private static let wheelHotkeyModifierFlags: NSEvent.ModifierFlags = [.shift, .command]

    /// Mirrors the CGEvent tap's view of "is the combo currently held".
    /// Mutated only inside the tap callback (which runs on the main
    /// run loop) so reads from the main thread are safe.
    @Published private(set) var isHotkeyCurrentlyPressed = false

    private var globalEventTap: CFMachPort?
    private var globalEventTapRunLoopSource: CFRunLoopSource?

    deinit {
        stop()
    }

    func start() {
        // Idempotent — calling start() repeatedly during permission
        // refreshes shouldn't reset the held state and clobber an
        // active wheel session.
        guard globalEventTap == nil else { return }

        let monitoredEventTypes: [CGEventType] = [.flagsChanged]
        let eventMask = monitoredEventTypes.reduce(CGEventMask(0)) { currentMask, eventType in
            currentMask | (CGEventMask(1) << eventType.rawValue)
        }

        let eventTapCallback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let personaWheelHotkeyMonitor = Unmanaged<PersonaWheelHotkeyMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            personaWheelHotkeyMonitor.handleGlobalEventTap(
                eventType: eventType,
                event: event
            )

            return Unmanaged.passUnretained(event)
        }

        guard let createdEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ Persona wheel hotkey: couldn't create CGEvent tap")
            return
        }

        guard let createdRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            createdEventTap,
            0
        ) else {
            CFMachPortInvalidate(createdEventTap)
            print("⚠️ Persona wheel hotkey: couldn't create run loop source")
            return
        }

        self.globalEventTap = createdEventTap
        self.globalEventTapRunLoopSource = createdRunLoopSource

        CFRunLoopAddSource(CFRunLoopGetMain(), createdRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: createdEventTap, enable: true)
    }

    func stop() {
        isHotkeyCurrentlyPressed = false

        if let globalEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
            self.globalEventTapRunLoopSource = nil
        }

        if let globalEventTap {
            CFMachPortInvalidate(globalEventTap)
            self.globalEventTap = nil
        }
    }

    private func handleGlobalEventTap(
        eventType: CGEventType,
        event: CGEvent
    ) {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let globalEventTap {
                CGEvent.tapEnable(tap: globalEventTap, enable: true)
            }
            return
        }

        guard eventType == .flagsChanged else { return }

        let modifierFlagsAsAppKit = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            .intersection(.deviceIndependentFlagsMask)

        let isComboCurrentlyHeld = modifierFlagsAsAppKit.isSuperset(of: Self.wheelHotkeyModifierFlags)

        if isComboCurrentlyHeld && !isHotkeyCurrentlyPressed {
            isHotkeyCurrentlyPressed = true
            hotkeyTransitionPublisher.send(.pressed)
        } else if !isComboCurrentlyHeld && isHotkeyCurrentlyPressed {
            isHotkeyCurrentlyPressed = false
            hotkeyTransitionPublisher.send(.released)
        }
    }
}
