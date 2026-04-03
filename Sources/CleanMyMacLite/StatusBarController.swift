import SwiftUI
import AppKit

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var monitor: SystemMonitor
    private var hostingView: VibrantHostingView<BlimpMenuView>?
    
    init(_ monitor: SystemMonitor) {
        self.monitor = monitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        super.init()
        
        if let button = statusItem.button {
            let blimpView = BlimpMenuView(monitor: monitor)
            let hostingView = VibrantHostingView(rootView: blimpView)
            
            // Set frame for the hosting view
            hostingView.frame = NSRect(x: 0, y: 0, width: 40, height: 22)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = .clear
            button.addSubview(hostingView)
            button.frame = hostingView.frame
            
            // Handle clicks
            button.target = self
            button.action = #selector(handleAction)
            
            self.hostingView = hostingView
        }
    }
    
    @objc func handleAction() {
        // Trigger cleaning and animation
        monitor.performFullCleanup()
        
        // Notify the SwiftUI view to animate
        // We can use a notification or a published property in monitor
        // Actually, we can add an 'isAnimating' property to SystemMonitor or just use the existing cleanup flags.
    }
}

struct BlimpMenuView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var offset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            if let nsImage = NSImage(contentsOfFile: "/Users/mathieu/Documents/Projects/Others/CleanMyMacLite/Blimp.svg") {
                let _ = { nsImage.isTemplate = true }()
                Image(nsImage: nsImage)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 25)
                    .foregroundColor(.primary) // Ensure it uses the primary system color (black/white)
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(rotation))
                    .offset(y: offset)
                    .onReceive(monitor.$isFreeingRAM.combineLatest(monitor.$isCleaningStorage)) { freeing, cleaning in
                        if freeing || cleaning {
                            if !isAnimating {
                                startAnimation()
                            }
                        } else {
                            stopAnimation()
                        }
                    }
            } else {
                // Fallback to SF Symbol if SVG not found
                Image(systemName: "airplane")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .offset(y: offset)
            }
        }
        .frame(width: 40, height: 22)
    }
    
    private func startAnimation() {
        isAnimating = true
        // Floaty flying animation
        withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            offset = -3
            rotation = 2
            scale = 1.05
        }
    }
    
    private func stopAnimation() {
        isAnimating = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            offset = 0
            rotation = 0
            scale = 1.0
        }
    }
}

class VibrantHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool {
        return true
    }
}
