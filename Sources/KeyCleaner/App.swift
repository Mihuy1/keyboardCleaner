import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        
        // Set accessory activation policy so app lives strictly in the status bar (no Dock icon)
        app.setActivationPolicy(.accessory)
        
        app.run()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize Status Item Manager
        _ = StatusItemManager.shared
        
        // Quietly check system permissions
        KeyboardBlocker.shared.checkPermission()
    }
}
