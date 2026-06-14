import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

struct FileGroup {
    let name: String
    let tag: String         // Short display tag, e.g. "DMG"
    let description: String
    var items: [URL]
    var totalSize: Int64
    var isSelected: Bool = false
}

class DiskAnalyzer: @unchecked Sendable {

    // MARK: - Size helpers

    /// Fast folder size using `du` on POSIX, Swift enumeration on Windows.
    static func sizeOfDir(_ path: String) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        #if os(Windows)
        return SystemMonitor.dirSize(path)
        #else
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        task.arguments = ["-sk", path]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
        try? task.run(); task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if let tok = out.split(separator: "\t").first, let kb = Int64(tok.trimmingCharacters(in: .whitespaces)) {
            return kb * 1024
        }
        return SystemMonitor.dirSize(path)
        #endif
    }

    static func sizeOfFile(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }

    // MARK: - Snipe groups

    func buildGroups() -> [FileGroup] {
        var groups: [FileGroup] = []
        groups += commonGroups()
        #if os(macOS)
        groups += macOSGroups()
        #elseif os(Linux)
        groups += linuxGroups()
        #elseif os(Windows)
        groups += windowsGroups()
        #endif
        return groups.filter { $0.totalSize > 0 }.sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - Common groups (all platforms)

    private func commonGroups() -> [FileGroup] {
        var groups: [FileGroup] = []
        let dl = Platform.downloads

        // Archives
        let archives = files(in: dl, exts: ["zip","tar","gz","bz2","7z","rar","xz","tgz"], recursive: false)
        if !archives.isEmpty {
            groups.append(FileGroup(name: "Archives", tag: "ZIP",
                description: "Compressed archives in ~/Downloads",
                items: archives,
                totalSize: archives.reduce(0) { $0 + Self.sizeOfFile($1) }))
        }

        // Old downloads (60+ days untouched)
        let old = oldFiles(in: dl, olderThanDays: 60)
        if !old.isEmpty {
            groups.append(FileGroup(name: "Old Downloads (60d+)", tag: "OLD",
                description: "Not accessed in 60+ days",
                items: old,
                totalSize: old.reduce(0) { $0 + Self.sizeOfFile($1) }))
        }

        // Large videos (>100 MB) in Downloads + Movies/Videos
        let videoDirs: [URL] = [dl, Platform.home.appendingPathComponent("Movies"),
                                    Platform.home.appendingPathComponent("Videos")]
        var videos: [URL] = []
        for dir in videoDirs {
            videos += files(in: dir, exts: ["mp4","mov","mkv","avi","m4v","wmv","webm"], recursive: true)
                .filter { Self.sizeOfFile($0) > 100 * 1024 * 1024 }
        }
        if !videos.isEmpty {
            groups.append(FileGroup(name: "Large Videos (>100MB)", tag: "VID",
                description: "Video files over 100 MB",
                items: videos,
                totalSize: videos.reduce(0) { $0 + Self.sizeOfFile($1) }))
        }

        return groups
    }

    // MARK: - macOS-specific groups

    #if os(macOS)
    private func macOSGroups() -> [FileGroup] {
        var groups: [FileGroup] = []
        let fm   = FileManager.default
        let home = Platform.home
        let dl   = Platform.downloads

        // DMG installers
        let dmgs = files(in: dl, exts: ["dmg"], recursive: false)
        if !dmgs.isEmpty {
            groups.append(FileGroup(name: "DMG Installers", tag: "DMG",
                description: "Disk images in ~/Downloads",
                items: dmgs, totalSize: dmgs.reduce(0) { $0 + Self.sizeOfFile($1) }))
        }

        // PKG installers
        let pkgs = files(in: dl, exts: ["pkg"], recursive: false)
        if !pkgs.isEmpty {
            groups.append(FileGroup(name: "PKG Installers", tag: "PKG",
                description: "Package installers in ~/Downloads",
                items: pkgs, totalSize: pkgs.reduce(0) { $0 + Self.sizeOfFile($1) }))
        }

        // Xcode DerivedData
        let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if let entries = try? fm.contentsOfDirectory(at: derived, includingPropertiesForKeys: nil)
                                .filter({ !$0.lastPathComponent.hasPrefix(".") }), !entries.isEmpty {
            let size = entries.reduce(0) { $0 + Self.sizeOfDir($1.path) }
            groups.append(FileGroup(name: "Xcode DerivedData", tag: "XCD",
                description: "Xcode build artifacts (safe to delete)",
                items: entries, totalSize: size))
        }

        // Xcode Archives
        let xarchRoot = home.appendingPathComponent("Library/Developer/Xcode/Archives")
        if let yearDirs = try? fm.contentsOfDirectory(at: xarchRoot, includingPropertiesForKeys: nil) {
            var xcarchives: [URL] = []
            for y in yearDirs {
                if let sub = try? fm.contentsOfDirectory(at: y, includingPropertiesForKeys: nil) {
                    xcarchives += sub.filter { $0.pathExtension == "xcarchive" }
                }
            }
            if !xcarchives.isEmpty {
                let size = xcarchives.reduce(0) { $0 + Self.sizeOfDir($1.path) }
                groups.append(FileGroup(name: "Xcode Archives", tag: "XCA",
                    description: "App build archives", items: xcarchives, totalSize: size))
            }
        }

        // iOS Simulators
        let simDevices = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        if let sims = try? fm.contentsOfDirectory(at: simDevices, includingPropertiesForKeys: nil)
                               .filter({ !$0.lastPathComponent.hasPrefix(".") }), !sims.isEmpty {
            groups.append(FileGroup(name: "iOS Simulators", tag: "SIM",
                description: "Simulator device data",
                items: sims, totalSize: Self.sizeOfDir(simDevices.path)))
        }

        // iOS Backups
        let backups = home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        if let bks = try? fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
                             .filter({ !$0.lastPathComponent.hasPrefix(".") }), !bks.isEmpty {
            let size = bks.reduce(0) { $0 + Self.sizeOfDir($1.path) }
            groups.append(FileGroup(name: "iOS Backups", tag: "BCK",
                description: "iPhone/iPad local backups", items: bks, totalSize: size))
        }

        // Homebrew Cache
        for p in [home.appendingPathComponent("Library/Caches/Homebrew").path,
                  "/opt/homebrew/Library/Homebrew/vendor"] {
            if fm.fileExists(atPath: p) {
                let url = URL(fileURLWithPath: p); let size = Self.sizeOfDir(p)
                if size > 1024 * 1024 {
                    groups.append(FileGroup(name: "Homebrew Cache", tag: "BRW",
                        description: "Homebrew download cache", items: [url], totalSize: size))
                    break
                }
            }
        }

        // User Logs
        let logsURL = Platform.logs
        if let logItems = try? fm.contentsOfDirectory(at: logsURL, includingPropertiesForKeys: nil)
                                   .filter({ !$0.lastPathComponent.hasPrefix(".") }), !logItems.isEmpty {
            groups.append(FileGroup(name: "Log Files", tag: "LOG",
                description: "User application logs",
                items: logItems, totalSize: Self.sizeOfDir(logsURL.path)))
        }

        // Trash
        let trashURL = Platform.trash
        if let trashItems = try? fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
                                     .filter({ !$0.lastPathComponent.hasPrefix(".") }), !trashItems.isEmpty {
            groups.append(FileGroup(name: "Trash", tag: "TRS",
                description: "Items waiting in the Trash",
                items: trashItems, totalSize: Self.sizeOfDir(trashURL.path)))
        }

        return groups
    }
    #endif

    // MARK: - Linux-specific groups

    #if os(Linux)
    private func linuxGroups() -> [FileGroup] {
        var groups: [FileGroup] = []
        let fm   = FileManager.default
        let home = Platform.home

        // Developer caches
        let devCaches: [(String, String, String)] = [
            ("npm Cache",      ".npm/_cacache",          "NPM"),
            ("yarn Cache",     ".yarn/cache",            "YRN"),
            ("pip Cache",      ".cache/pip",             "PIP"),
            ("Gradle Caches",  ".gradle/caches",         "GRD"),
            ("Maven Repo",     ".m2/repository",         "MVN"),
            ("Cargo Registry", ".cargo/registry/cache",  "CRG"),
            ("Go Mod Cache",   "go/pkg/mod/cache",       "GOM"),
        ]
        for (name, rel, tag) in devCaches {
            let url  = home.appendingPathComponent(rel)
            let size = Self.sizeOfDir(url.path)
            if size > 1024 * 1024 {
                groups.append(FileGroup(name: name, tag: tag,
                    description: url.path, items: [url], totalSize: size))
            }
        }

        // ~/.cache subdirectories (each as its own entry)
        let cacheRoot = Platform.cache
        if let entries = try? fm.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil)
                                 .filter({ !$0.lastPathComponent.hasPrefix(".") }) {
            let big = entries.filter { Self.sizeOfDir($0.path) > 50 * 1024 * 1024 }
            if !big.isEmpty {
                let size = big.reduce(0) { $0 + Self.sizeOfDir($1.path) }
                groups.append(FileGroup(name: "Large Cache Dirs (>50MB)", tag: "CHE",
                    description: "Entries in ~/.cache larger than 50 MB",
                    items: big, totalSize: size))
            }
        }

        // Trash
        let trashURL = Platform.trash
        if let trashItems = try? fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
                                     .filter({ !$0.lastPathComponent.hasPrefix(".") }), !trashItems.isEmpty {
            groups.append(FileGroup(name: "Trash", tag: "TRS",
                description: "~/.local/share/Trash/files",
                items: trashItems, totalSize: Self.sizeOfDir(trashURL.path)))
        }

        // /tmp (files you own only — best effort)
        let myUID = Int(getuid())
        let tmp   = URL(fileURLWithPath: "/tmp")
        if let all = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            let items = all.filter { url in
                guard let owner = (try? fm.attributesOfItem(atPath: url.path))?[.ownerAccountID] as? NSNumber
                else { return false }
                return owner.intValue == myUID
            }
            let size = items.reduce(0) { $0 + Self.sizeOfFile($1) }
            if size > 1024 * 1024 {
                groups.append(FileGroup(name: "Your /tmp Files", tag: "TMP",
                    description: "Temp files you own in /tmp",
                    items: items, totalSize: size))
            }
        }

        return groups
    }
    #endif

    // MARK: - Windows-specific groups

    #if os(Windows)
    private func windowsGroups() -> [FileGroup] {
        var groups: [FileGroup] = []
        let fm   = FileManager.default
        let home = Platform.home

        // %TEMP%
        let tempURL = Platform.temp
        if let items = try? fm.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil)
                               .filter({ !$0.lastPathComponent.hasPrefix(".") }), !items.isEmpty {
            let size = Self.sizeOfDir(tempURL.path)
            groups.append(FileGroup(name: "Temp Folder", tag: "TMP",
                description: "%TEMP%", items: items, totalSize: size))
        }

        // Developer caches
        let appData  = ProcessInfo.processInfo.environment["APPDATA"]
                    ?? home.appendingPathComponent("AppData/Roaming").path
        let localAD  = ProcessInfo.processInfo.environment["LOCALAPPDATA"]
                    ?? home.appendingPathComponent("AppData/Local").path
        let devCaches: [(String, String, String)] = [
            ("npm Cache",   appData  + "\\npm-cache",          "NPM"),
            ("pip Cache",   localAD  + "\\pip\\Cache",         "PIP"),
            ("yarn Cache",  localAD  + "\\Yarn\\Cache",        "YRN"),
            ("Gradle Cache",home.appendingPathComponent(".gradle/caches").path, "GRD"),
            ("Maven Repo",  home.appendingPathComponent(".m2/repository").path, "MVN"),
        ]
        for (name, path, tag) in devCaches {
            let url  = URL(fileURLWithPath: path)
            let size = Self.sizeOfDir(path)
            if size > 1024 * 1024 {
                groups.append(FileGroup(name: name, tag: tag,
                    description: path, items: [url], totalSize: size))
            }
        }

        return groups
    }
    #endif

    // MARK: - Disk usage scan

    func scanDiskUsage() -> [(name: String, path: String, size: Int64)] {
        let home  = Platform.home
        var dirs: [(String, String)] = [
            ("Downloads",           home.appendingPathComponent("Downloads").path),
            ("Desktop",             home.appendingPathComponent("Desktop").path),
            ("Documents",           home.appendingPathComponent("Documents").path),
            ("Cache",               Platform.cache.path),
            ("Logs",                Platform.logs.path),
        ]
        #if os(macOS)
        dirs += [
            ("Movies",              home.appendingPathComponent("Movies").path),
            ("Music",               home.appendingPathComponent("Music").path),
            ("Pictures",            home.appendingPathComponent("Pictures").path),
            ("Library/App Support", home.appendingPathComponent("Library/Application Support").path),
            ("Xcode DerivedData",   home.appendingPathComponent("Library/Developer/Xcode/DerivedData").path),
            ("iOS Simulators",      home.appendingPathComponent("Library/Developer/CoreSimulator/Devices").path),
        ]
        #elseif os(Linux)
        dirs += [
            ("Videos",              home.appendingPathComponent("Videos").path),
            ("Music",               home.appendingPathComponent("Music").path),
            ("Pictures",            home.appendingPathComponent("Pictures").path),
            (".local/share",        home.appendingPathComponent(".local/share").path),
        ]
        #elseif os(Windows)
        let lad = ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? ""
        if !lad.isEmpty { dirs.append(("AppData/Local", lad)) }
        dirs += [
            ("Videos",     home.appendingPathComponent("Videos").path),
            ("Music",      home.appendingPathComponent("Music").path),
            ("Pictures",   home.appendingPathComponent("Pictures").path),
        ]
        #endif
        return dirs.map { (name: $0.0, path: $0.1, size: Self.sizeOfDir($0.1)) }
                   .filter { $0.size > 0 }
                   .sorted { $0.size > $1.size }
    }

    // MARK: - Private helpers

    private func files(in dir: URL, exts: [String], recursive: Bool) -> [URL] {
        let opts: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles]
            : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        guard let e = FileManager.default.enumerator(at: dir,
                includingPropertiesForKeys: [.isRegularFileKey], options: opts) else { return [] }
        var result: [URL] = []
        for case let url as URL in e {
            if exts.contains(url.pathExtension.lowercased()) { result.append(url) }
        }
        return result
    }

    private func oldFiles(in dir: URL, olderThanDays days: Int) -> [URL] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        guard let e = FileManager.default.enumerator(at: dir,
                includingPropertiesForKeys: [.contentAccessDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else { return [] }
        var result: [URL] = []
        for case let url as URL in e {
            if let v = try? url.resourceValues(forKeys: [.contentAccessDateKey, .isRegularFileKey]),
               v.isRegularFile == true,
               let d = v.contentAccessDate, d < cutoff { result.append(url) }
        }
        return result
    }
}

// MARK: - getuid shim for non-Linux
#if !os(Linux) && !os(macOS) && !os(Windows)
private func getuid() -> UInt32 { 0 }
#elseif os(Windows)
private func getuid() -> UInt32 { 0 }
#endif
