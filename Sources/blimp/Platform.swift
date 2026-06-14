import Foundation

// Central platform abstraction — every OS-specific path and name goes here.
enum Platform {

    // MARK: - OS detection

    static var isMacOS:   Bool { _isMacOS }
    static var isLinux:   Bool { _isLinux }
    static var isWindows: Bool { _isWindows }

    static var osName: String {
        #if os(macOS)
        return "macOS"
        #elseif os(Linux)
        return "Linux"
        #elseif os(Windows)
        return "Windows"
        #else
        return "Unknown"
        #endif
    }

    // MARK: - Key directories (as URL)

    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var cache: URL {
        #if os(macOS)
        return home.appendingPathComponent("Library/Caches")
        #elseif os(Windows)
        let lad = ProcessInfo.processInfo.environment["LOCALAPPDATA"]
                   ?? home.appendingPathComponent("AppData/Local").path
        return URL(fileURLWithPath: lad)
        #else
        let xdg = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] ?? ""
        return xdg.isEmpty ? home.appendingPathComponent(".cache") : URL(fileURLWithPath: xdg)
        #endif
    }

    static var logs: URL {
        #if os(macOS)
        return home.appendingPathComponent("Library/Logs")
        #elseif os(Windows)
        return cache.appendingPathComponent("Logs")
        #else
        return home.appendingPathComponent(".local/share/logs")
        #endif
    }

    static var temp: URL {
        #if os(Windows)
        let t = ProcessInfo.processInfo.environment["TEMP"]
             ?? ProcessInfo.processInfo.environment["TMP"]
             ?? "C:\\Temp"
        return URL(fileURLWithPath: t)
        #else
        return URL(fileURLWithPath: "/tmp")
        #endif
    }

    static var trash: URL {
        #if os(macOS)
        return home.appendingPathComponent(".Trash")
        #elseif os(Windows)
        // Best-effort: recycle bin is per-drive, this is just the user profile one
        return home.appendingPathComponent("$Recycle.Bin")
        #else
        return home.appendingPathComponent(".local/share/Trash/files")
        #endif
    }

    static var downloads: URL { home.appendingPathComponent("Downloads") }

    // MARK: - Private compile-time constants

    #if os(macOS)
    private static let _isMacOS   = true
    private static let _isLinux   = false
    private static let _isWindows = false
    #elseif os(Linux)
    private static let _isMacOS   = false
    private static let _isLinux   = true
    private static let _isWindows = false
    #elseif os(Windows)
    private static let _isMacOS   = false
    private static let _isLinux   = false
    private static let _isWindows = true
    #else
    private static let _isMacOS   = false
    private static let _isLinux   = true
    private static let _isWindows = false
    #endif
}
