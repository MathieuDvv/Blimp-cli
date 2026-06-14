import Foundation

struct AppInfo {
    let name: String
    let path: URL
    let bundleIdentifier: String?
}

// App management is only meaningful on macOS (bundle-based apps + AppleScript sudo).
// On Linux/Windows we expose the type but return empty results.

#if os(macOS)
import AppKit

class AppManager: @unchecked Sendable {

    func listApps(installedOnly: Bool = false) -> [AppInfo] {
        var apps: [AppInfo] = []
        let fm = FileManager.default
        let searchPaths = ["/Applications", Platform.home.appendingPathComponent("Applications").path]
        for pathStr in searchPaths {
            guard let e = fm.enumerator(atPath: pathStr) else { continue }
            for case let file as String in e {
                guard file.hasSuffix(".app"),
                      file.components(separatedBy: "/").count <= 2 else { continue }
                let url    = URL(fileURLWithPath: pathStr + "/" + file)
                let bundle = Bundle(url: url)
                let name   = (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                          ?? (bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)
                          ?? url.deletingPathExtension().lastPathComponent
                let bid    = bundle?.bundleIdentifier
                if installedOnly && pathStr == "/Applications" {
                    if bid?.hasPrefix("com.apple.") == true { e.skipDescendants(); continue }
                    if url.path.hasPrefix("/System/")        { e.skipDescendants(); continue }
                }
                apps.append(AppInfo(name: name, path: url, bundleIdentifier: bid))
                e.skipDescendants()
            }
        }
        return apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func searchApps(query: String) -> [AppInfo] {
        let q = query.lowercased()
        return listApps(installedOnly: false).filter {
            $0.name.lowercased().contains(q) || $0.path.lastPathComponent.lowercased().contains(q)
        }
    }

    func uninstallApp(app: AppInfo) -> String {
        var paths = [app.path.path]
        var log   = "Found \(app.name) at \(app.path.path)\n"
        if let bid = app.bundleIdentifier {
            let home = Platform.home.path
            paths += [
                "\(home)/Library/Application Support/\(app.name)",
                "\(home)/Library/Caches/\(bid)",
                "\(home)/Library/Preferences/\(bid).plist",
                "\(home)/Library/Saved Application State/\(bid).savedState",
            ]
        }
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        log += "Files to delete:\n" + existing.map { "  - \($0)" }.joined(separator: "\n") + "\n"
        let args   = existing.map { "'\($0)'" }.joined(separator: " ")
        let script = "do shell script \"rm -rf \(args)\" with administrator privileges"
        guard let as_ = NSAppleScript(source: script) else { return log + "AppleScript init failed." }
        var err: NSDictionary?
        as_.executeAndReturnError(&err)
        return err != nil ? log + "Failed: \(err!)" : log + "Successfully uninstalled \(app.name)."
    }
}

#else

class AppManager: @unchecked Sendable {
    func listApps(installedOnly: Bool = false) -> [AppInfo] { [] }
    func searchApps(query: String) -> [AppInfo] { [] }
    func uninstallApp(app: AppInfo) -> String { "App management is macOS-only." }
}

#endif
