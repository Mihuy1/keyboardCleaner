import AppKit
import SwiftUI
import Combine

final class StatusItemManager: NSObject, NSMenuDelegate {
    static let shared = StatusItemManager()
    
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var menu: NSMenu!
    
    private var toggleMenuItem: NSMenuItem!
    private var countMenuItem: NSMenuItem!
    private var permissionMenuItem: NSMenuItem!
    
    override private init() {
        super.init()
        setupStatusItem()
        observeBlocker()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyCleaner")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        
        // Title item
        let titleItem = NSMenuItem(title: "KeyCleaner", action: nil, keyEquivalent: "")
        let font = NSFont.boldSystemFont(ofSize: 13)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        titleItem.attributedTitle = NSAttributedString(string: "KeyCleaner 🧼", attributes: attributes)
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Toggle Lock MenuItem
        toggleMenuItem = NSMenuItem(title: "🔒 Lock Keyboard", action: #selector(toggleLockClicked), keyEquivalent: "l")
        toggleMenuItem.target = self
        toggleMenuItem.isEnabled = true
        menu.addItem(toggleMenuItem)
        
        // Blocked Count MenuItem
        countMenuItem = NSMenuItem(title: "Blocked Keypresses: 0", action: nil, keyEquivalent: "")
        countMenuItem.isEnabled = false
        menu.addItem(countMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Permission Status / Fix
        permissionMenuItem = NSMenuItem(title: "Checking Keyboard Blocking Availability...", action: nil, keyEquivalent: "")
        permissionMenuItem.isEnabled = false
        menu.addItem(permissionMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit Item
        let quitItem = NSMenuItem(title: "Quit KeyCleaner", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)
        
        // Keep the menu detached so the status-item button receives both left- and
        // right-click actions. Assigning it to statusItem.menu makes AppKit open the
        // menu directly and bypass statusItemClicked(_:).
    }
    
    private func observeBlocker() {
        let blocker = KeyboardBlocker.shared
        
        blocker.$isLocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLocked in
                self?.updateUI(isLocked: isLocked, blockedCount: blocker.blockedCount, availability: blocker.eventTapAvailability)
                
                if isLocked {
                    LockOverlayWindow.shared.showHUD()
                } else {
                    LockOverlayWindow.shared.hideHUD()
                }
            }
            .store(in: &cancellables)
        
        blocker.$blockedCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.updateUI(isLocked: blocker.isLocked, blockedCount: count, availability: blocker.eventTapAvailability)
            }
            .store(in: &cancellables)
        
        blocker.$eventTapAvailability
            .receive(on: DispatchQueue.main)
            .sink { [weak self] availability in
                self?.updateUI(isLocked: blocker.isLocked, blockedCount: blocker.blockedCount, availability: availability)
            }
            .store(in: &cancellables)
    }
    
    private func updateUI(isLocked: Bool, blockedCount: Int, availability: EventTapAvailability) {
        guard let button = statusItem.button else { return }
        
        if isLocked {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            if let baseImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Keyboard Locked")?.withSymbolConfiguration(config) {
                let redImage = baseImage.tinted(with: .systemRed)
                button.image = redImage
            }
            button.title = " LOCKED"
            toggleMenuItem.title = "🔓 Unlock Keyboard"
        } else {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            if let baseImage = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyCleaner")?.withSymbolConfiguration(config) {
                baseImage.isTemplate = true
                button.image = baseImage
            }
            button.title = ""
            toggleMenuItem.title = "🔒 Lock Keyboard"
        }
        
        countMenuItem.title = "Blocked Keypresses: \(blockedCount)"
        
        if availability == .available {
            permissionMenuItem.title = "Keyboard Blocking: Available ✅"
            permissionMenuItem.target = nil
            permissionMenuItem.action = nil
            permissionMenuItem.isEnabled = false
        } else {
            switch availability {
            case .accessibilityRequired:
                permissionMenuItem.title = "⚠️ Keyboard Blocking Unavailable — Grant Accessibility Access..."
            case .unavailable:
                permissionMenuItem.title = "⚠️ Keyboard Blocking Unavailable — Open Accessibility Settings..."
            case .available:
                break
            }
            permissionMenuItem.target = self
            permissionMenuItem.action = #selector(permissionClicked)
            permissionMenuItem.isEnabled = true
        }
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        KeyboardBlocker.shared.refreshEventTapAvailability()
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        KeyboardBlocker.shared.refreshEventTapAvailability()
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            KeyboardBlocker.shared.toggleLock()
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
    
    @objc private func toggleLockClicked() {
        KeyboardBlocker.shared.toggleLock()
    }
    
    @objc private func permissionClicked() {
        KeyboardBlocker.shared.openAccessibilitySettings()
    }
    
    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
}

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return self
        }
        let tintedImage = NSImage(size: self.size)
        tintedImage.isTemplate = false
        tintedImage.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            let rect = CGRect(origin: .zero, size: self.size)
            context.clip(to: rect, mask: cgImage)
            color.setFill()
            context.fill(rect)
        }
        tintedImage.unlockFocus()
        return tintedImage
    }
}
