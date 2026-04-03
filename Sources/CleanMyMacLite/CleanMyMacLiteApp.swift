import SwiftUI
import AppKit

@main
struct CleanMyMacLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private let monitor = SystemMonitor()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent multiple instances
        let currentApp = NSRunningApplication.current
        let otherInstances = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == currentApp.bundleIdentifier &&
            $0.processIdentifier != currentApp.processIdentifier
        }
        
        // If bundleIdentifier is nil (running as raw binary), check by name
        if currentApp.bundleIdentifier == nil {
            let otherByName = NSWorkspace.shared.runningApplications.filter {
                $0.localizedName == "CleanMyMacLite" &&
                $0.processIdentifier != currentApp.processIdentifier
            }
            if !otherByName.isEmpty {
                NSApp.terminate(nil)
                return
            }
        } else if !otherInstances.isEmpty {
            NSApp.terminate(nil)
            return
        }

        // Hide the dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize the status bar controller
        statusBar = StatusBarController(monitor)
    }
}
