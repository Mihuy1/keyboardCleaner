import SwiftUI
import AppKit

final class LockOverlayWindow: NSPanel {
    static let shared = LockOverlayWindow()
    
    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        
        let contentView = NSHostingView(rootView: LockOverlayView())
        self.contentView = contentView
        
        centerTop()
    }
    
    func centerTop() {
        if let mainScreen = NSScreen.main {
            let screenFrame = mainScreen.visibleFrame
            let windowWidth: CGFloat = 340
            let windowHeight: CGFloat = 140
            let x = screenFrame.midX - (windowWidth / 2)
            let y = screenFrame.maxY - windowHeight - 20
            self.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        }
    }
    
    func showHUD() {
        centerTop()
        self.orderFrontRegardless()
    }
    
    func hideHUD() {
        self.orderOut(nil)
    }
}

struct LockOverlayView: View {
    @ObservedObject var blocker = KeyboardBlocker.shared
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.red)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keyboard Locked")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Clean your keyboard freely 🧼")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
            }
            
            HStack {
                Text("\(blocker.blockedCount) keypresses blocked")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Button(action: {
                    blocker.unlock()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.open.fill")
                        Text("Unlock")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .frame(width: 340, height: 140)
    }
}
