import Foundation
import AppKit

struct AppInfo {
    let name: String
    let path: URL
    let bundleIdentifier: String?
}

class AppManager: @unchecked Sendable {
    func listApps(installedOnly: Bool = false) -> [AppInfo] {
        var apps: [AppInfo] = []
        let fileManager = FileManager.default
        let searchPaths = ["/Applications", NSHomeDirectory() + "/Applications"]

        for pathStr in searchPaths {
            guard let enumerator = fileManager.enumerator(atPath: pathStr) else { continue }
            for case let file as String in enumerator {
                if file.hasSuffix(".app") {
                    let fullPath = URL(fileURLWithPath: pathStr + "/" + file)
                    if file.components(separatedBy: "/").count > 2 { continue }

                    let bundle = Bundle(url: fullPath)
                    let name = (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? (bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)
                        ?? fullPath.deletingPathExtension().lastPathComponent
                    let bundleId = bundle?.bundleIdentifier

                    if installedOnly {
                        if pathStr == "/Applications" {
                            if let bid = bundleId, bid.starts(with: "com.apple.") {
                                enumerator.skipDescendants()
                                continue
                            }
                            if fullPath.path.hasPrefix("/System/") {
                                enumerator.skipDescendants()
                                continue
                            }
                        }
                    }

                    apps.append(AppInfo(name: name, path: fullPath, bundleIdentifier: bundleId))
                    enumerator.skipDescendants()
                }
            }
        }
        return apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func searchApps(query: String) -> [AppInfo] {
        let apps = listApps(installedOnly: false)
        let q = query.lowercased()
        return apps.filter {
            $0.name.lowercased().contains(q)
                || $0.path.lastPathComponent.lowercased().contains(q)
        }
    }

    func uninstallApp(app: AppInfo) -> String {
        var pathsToDelete: [String] = [app.path.path]
        var log = "Found \(app.name) at \(app.path.path)\n"

        if let bundleId = app.bundleIdentifier {
            let home = NSHomeDirectory()
            let supportPath = "\(home)/Library/Application Support/\(app.name)"
            let cachePath = "\(home)/Library/Caches/\(bundleId)"
            let prefsPath = "\(home)/Library/Preferences/\(bundleId).plist"
            let statePath = "\(home)/Library/Saved Application State/\(bundleId).savedState"

            pathsToDelete.append(supportPath)
            pathsToDelete.append(cachePath)
            pathsToDelete.append(prefsPath)
            pathsToDelete.append(statePath)
        }

        let existingPaths = pathsToDelete.filter { FileManager.default.fileExists(atPath: $0) }
        log += "Associated files to delete:\n"
        for p in existingPaths {
            log += " - \(p)\n"
        }

        let arguments = existingPaths.map { "'\($0)'" }.joined(separator: " ")
        let scriptStr = "do shell script \"rm -rf \(arguments)\" with administrator privileges"

        guard let appleScript = NSAppleScript(source: scriptStr) else {
            return log + "Failed to initialize AppleScript."
        }

        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)

        if let err = error {
            return log + "Failed to uninstall: \(err)"
        }

        return log + "Successfully uninstalled \(app.name)."
    }
}
