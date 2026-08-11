import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

enum EventTapAvailability: Equatable {
    case available
    case accessibilityRequired
    case unavailable
}

final class KeyboardBlocker: ObservableObject {
    static let shared = KeyboardBlocker()
    
    @Published var isLocked: Bool = false
    @Published var blockedCount: Int = 0
    @Published private(set) var eventTapAvailability: EventTapAvailability = .unavailable
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var previousFlags: CGEventFlags = []
    
    private init() {
        refreshEventTapAvailability()
    }
    
    @discardableResult
    func refreshEventTapAvailability() -> EventTapAvailability {
        let availability: EventTapAvailability

        if eventTap != nil || canCreateActiveKeyboardTap() {
            availability = .available
        } else if !AXIsProcessTrusted() {
            availability = .accessibilityRequired
        } else {
            availability = .unavailable
        }

        DispatchQueue.main.async {
            self.eventTapAvailability = availability
        }
        return availability
    }
    
    func toggleLock() {
        if isLocked {
            unlock()
        } else {
            lock()
        }
    }
    
    func lock() {
        guard !isLocked else { return }
        
        let availability = refreshEventTapAvailability()
        guard availability == .available else {
            if availability == .accessibilityRequired {
                requestAccessibilityPermission()
            }
            return
        }
        
        if !startEventTap() {
            DispatchQueue.main.async { self.eventTapAvailability = .unavailable }
            return
        }
        
        DispatchQueue.main.async { self.eventTapAvailability = .available }
        isLocked = true
        blockedCount = 0
    }
    
    func unlock() {
        guard isLocked else { return }
        stopEventTap()
        isLocked = false
    }
    
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func canCreateActiveKeyboardTap() -> Bool {
        // Probe with keyDown only. If Accessibility access is missing, macOS removes
        // keyboard events from an active tap's mask and creation returns nil.
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let probeTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, _, event, _ in
                Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            return false
        }

        CGEvent.tapEnable(tap: probeTap, enable: false)
        CFMachPortInvalidate(probeTap)
        return true
    }
    
    @discardableResult
    private func startEventTap() -> Bool {
        stopEventTap() // Ensure clean state
        previousFlags = []
        
        let eventMask: uint64 = (1 << CGEventType.keyDown.rawValue)
                              | (1 << CGEventType.keyUp.rawValue)
                              | (1 << CGEventType.flagsChanged.rawValue)
                              | (1 << 14) // 14 = sysDefined (Function keys & System Media keys)
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                
                let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(refcon).takeUnretainedValue()
                
                // Handle system disabling the event tap automatically on timeout
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = blocker.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                
                // If keyboard locked, consume event and increment counter accurately
                if blocker.isLocked {
                    var isNewPhysicalKeyPress = false
                    
                    if type == .keyDown {
                        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                        if !isRepeat {
                            isNewPhysicalKeyPress = true
                        }
                    } else if type.rawValue == 14 {
                        // System-Defined Media/Function keys (Volume, Brightness, Play/Pause, etc.)
                        if let nsEvent = NSEvent(cgEvent: event) {
                            let data1 = nsEvent.data1
                            let keyState = (data1 & 0xFF00) >> 8
                            // 0xa represents KeyDown for auxiliary media keys
                            if keyState == 0xa {
                                isNewPhysicalKeyPress = true
                            }
                        } else {
                            isNewPhysicalKeyPress = true
                        }
                    } else if type == .flagsChanged {
                        let currentFlags = event.flags
                        let relevantMasks: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskAlphaShift]
                        let newModifiers = currentFlags.intersection(relevantMasks)
                        let oldModifiers = blocker.previousFlags.intersection(relevantMasks)
                        
                        // Check if any new modifier key was pressed down
                        if !newModifiers.subtracting(oldModifiers).isEmpty {
                            isNewPhysicalKeyPress = true
                        }
                        blocker.previousFlags = currentFlags
                    }
                    
                    if isNewPhysicalKeyPress {
                        DispatchQueue.main.async {
                            blocker.blockedCount += 1
                        }
                    }
                    
                    return nil // Return nil to suppress all key events (including F-keys & media keys)
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPointer
        ) else {
            print("Failed to create event tap. Check Input Monitoring / Accessibility permissions.")
            return false
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    
    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                self.runLoopSource = nil
            }
            self.eventTap = nil
        }
    }
}
