import Foundation

struct BlimpConfig: Codable {
    struct Colors: Codable {
        var topBarBg: String = "#303030"
        var topBarFg: String = "#FFFFFF"
        var suggestion: String = "#808080"
        var historyDivider: String = "#404040"
        var bottomDivider: String = "#007AFF"
    }

    struct Commands: Codable {
        var clean: String = "/clean"
        var cleanRam: String = "/clean ram"
        var cleanCache: String = "/clean cache"
        var apps: String = "/apps"
        var appsInstalled: String = "/apps installed"
        var uninstall: String = "/uninstall "
        var blimp: String = "/blimp"
        var ui: String = "/ui"
        var uiAutostart: String = "/ui autostart"
        var uiQuit: String = "/ui quit"
        var config: String = "/config"
        var help: String = "/help"
        var quit: String = "/quit"
    }

    struct Misc: Codable {
        var barFill: String = "█"
        var barEmpty: String = "░"
    }

    var colors = Colors()
    var commands = Commands()
    var misc = Misc()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colors = try container.decodeIfPresent(Colors.self, forKey: .colors) ?? Colors()
        commands = try container.decodeIfPresent(Commands.self, forKey: .commands) ?? Commands()
        misc = try container.decodeIfPresent(Misc.self, forKey: .misc) ?? Misc()
    }
}

private enum UIBridge {
    static let executableName = "BlimpApp"
    static let launchAgentLabel = "com.mathieu.blimp.ui"

    static func executableURL() -> URL? {
        let fileManager = FileManager.default
        let currentExecutable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let executableDirectory = currentExecutable.deletingLastPathComponent()
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory())

        let candidates = [
            executableDirectory.appendingPathComponent(executableName),
            currentDirectory.appendingPathComponent(".build/debug/\(executableName)"),
            currentDirectory.appendingPathComponent(".build/release/\(executableName)"),
            homeDirectory.appendingPathComponent("Applications/\(executableName).app/Contents/MacOS/\(executableName)"),
            URL(fileURLWithPath: "/Applications/\(executableName).app/Contents/MacOS/\(executableName)")
        ]

        for candidate in candidates {
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}

class BlimpCLIApp {
    let monitor = SystemMonitor()
    let appManager = AppManager()

    var config = BlimpConfig()
    let configURL: URL
    var lastConfigModTime: Date? = nil

    var isRunning = true
    var currentInput = ""

    struct HistoryItem {
        let command: String
        var output: [String]
    }

    var history: [HistoryItem] = []
    var selectedHistoryIndex: Int? = nil

    var isExecuting = false
    var loaderFrame = 0
    let loaderChars = ["|", "/", "-", "\\"]

    var rows = 24
    var cols = 80
    let leftPaneWidthRatio = 0.3

    var easterEggFrame = 0
    var showingEasterEgg = false

    var activeAppPrompt: [AppInfo]? = nil
    var lastClickTime = Date.distantPast
    var lastClickIndex: Int? = nil

    var baseCommands: [String] {
        let cmd = config.commands
        return [
            cmd.clean, cmd.cleanRam, cmd.cleanCache,
            cmd.apps, cmd.appsInstalled, cmd.uninstall,
            cmd.blimp, cmd.ui, cmd.uiAutostart, cmd.uiQuit,
            cmd.config, cmd.help, cmd.quit
        ]
    }

    func hexToAnsi(_ hex: String, isBackground: Bool = false) -> String {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if cleanHex.count == 3 {
            let chs = Array(cleanHex)
            cleanHex = chs.map { String(repeating: $0, count: 2) }.joined()
        }
        guard cleanHex.count == 6, let rgb = Int(cleanHex, radix: 16) else { return "" }
        let r = (rgb >> 16) & 0xFF
        let g = (rgb >> 8) & 0xFF
        let b = rgb & 0xFF
        let typeStr = isBackground ? "48" : "38"
        return "\u{1B}[\(typeStr);2;\(r);\(g);\(b)m"
    }

    init() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let dir = home.appendingPathComponent(".config/blimp")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        configURL = dir.appendingPathComponent("config.json")
    }

    func checkConfig() {
        if !FileManager.default.fileExists(atPath: configURL.path) {
            saveConfig()
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path),
              let modDate = attrs[.modificationDate] as? Date else { return }

        if lastConfigModTime == nil || modDate > lastConfigModTime! {
            if let data = try? Data(contentsOf: configURL),
               let newConfig = try? JSONDecoder().decode(BlimpConfig.self, from: data) {
                self.config = newConfig
            }
            lastConfigModTime = modDate
        }
    }

    func saveConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL)
        }
    }

    func getHelpText() -> [String] {
        let cmd = config.commands
        let commands = [
            (cmd.clean, "Master system clean"),
            (cmd.cleanRam, "Vent gas (Memory)"),
            (cmd.cleanCache, "Drop cargo (Cache)"),
            (cmd.apps, "Scan all properties"),
            (cmd.appsInstalled, "Scan user properties"),
            ("\(cmd.uninstall)<name>", "Secure delete tool"),
            (cmd.ui, "Spawn Menu Bar UI"),
            (cmd.uiAutostart, "Toggle Auto-login"),
            (cmd.uiQuit, "Dismiss Menu Bar UI"),
            (cmd.config, "Customize system rules"),
            (cmd.help, "Display this matrix"),
            (cmd.quit, "Unplug")
        ]

        var lines = [
            "Blimp Core - System Manual",
            String(repeating: "─", count: 45)
        ]
        for c in commands {
            let leftPad = "  " + c.0.padding(toLength: 20, withPad: " ", startingAt: 0)
            lines.append("\(leftPad)  \(c.1)")
        }
        return lines
    }

    func run() {
        checkConfig()

        Terminal.enableRawMode()
        defer { Terminal.disableRawMode() }

        history.append(HistoryItem(command: "Welcome to Blimp CLI!", output: getHelpText()))
        selectedHistoryIndex = 0

        while isRunning {
            let size = Terminal.getWindowSize()
            rows = size.rows
            cols = size.cols

            monitor.loopTick()
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))

            checkConfig()

            if isExecuting { loaderFrame += 1 }
            if showingEasterEgg { easterEggFrame += 1 }

            drawFrame()

            if let keys = Terminal.readKey() {
                processKeys(keys: keys)
            }
        }
    }

    func processKeys(keys: [UInt8]) {
        if keys.count == 1 {
            let c = keys[0]
            if c == 127 || c == 8 {
                if !currentInput.isEmpty {
                    currentInput.removeLast()
                }
            } else if c == 13 || c == 10 {
                if let promptApps = activeAppPrompt {
                    if let num = Int(currentInput), num > 0, num <= promptApps.count {
                        currentInput = ""
                        activeAppPrompt = nil
                        executeUninstall(app: promptApps[num - 1])
                    } else {
                        currentInput = ""
                    }
                } else {
                    if currentInput.isEmpty {
                        if let sel = selectedHistoryIndex, sel < history.count {
                            let cmd = history[sel].command
                            if cmd.starts(with: "/") {
                                executeCommand(cmd)
                            }
                        }
                    } else {
                        executeCommand(currentInput)
                        currentInput = ""
                    }
                }
            } else if c == 3 {
                isRunning = false
            } else if c == 9 {
                let suggestion = getSuggestion()
                if !suggestion.isEmpty {
                    currentInput = suggestion
                }
            } else if c >= 32 && c <= 126 {
                currentInput.append(Character(UnicodeScalar(c)))
            } else if c == 27 {
                if activeAppPrompt != nil {
                    activeAppPrompt = nil
                    currentInput = ""
                } else {
                    isRunning = false
                }
            }
        } else if keys.count > 2 && keys[0] == 27 && keys[1] == 91 {
            if keys.count == 3 {
                if keys[2] == 65 {
                    moveSelection(1)
                } else if keys[2] == 66 {
                    moveSelection(-1)
                } else if keys[2] == 67 {
                    let suggestion = getSuggestion()
                    if !suggestion.isEmpty { currentInput = suggestion }
                }
            }
            if keys.count >= 6 && keys[2] == 60 {
                let str = String(bytes: keys.dropFirst(3), encoding: .ascii) ?? ""
                if str.hasSuffix("M") {
                    let parts = str.dropLast().split(separator: ";")
                    if parts.count >= 3, let x = Int(parts[1]), let y = Int(parts[2]) {
                        handleMouseClick(x: x, y: y)
                    }
                }
            }
        }
    }

    func getSuggestion() -> String {
        guard !currentInput.isEmpty else { return "" }
        if currentInput.hasPrefix(config.commands.uninstall) {
            return ""
        }
        for cmd in baseCommands {
            if cmd.hasPrefix(currentInput.lowercased()) {
                return cmd
            }
        }
        return ""
    }

    func handleMouseClick(x: Int, y: Int) {
        let leftWidth = max(10, Int(Double(cols) * leftPaneWidthRatio))
        let historyStartY = 3
        let now = Date()

        if activeAppPrompt != nil {
            let appIndex = y - historyStartY - 3
            if appIndex >= 0 && appIndex < activeAppPrompt!.count {
                let app = activeAppPrompt![appIndex]
                currentInput = ""
                activeAppPrompt = nil
                executeUninstall(app: app)
                return
            }
        }

        if x <= leftWidth && y >= historyStartY && y < rows - 2 {
            let listIndex = y - historyStartY
            if listIndex < history.count {
                let actualIndex = history.count - 1 - listIndex
                if let last = lastClickIndex,
                   last == actualIndex,
                   now.timeIntervalSince(lastClickTime) < 0.4 {
                    let cmd = history[actualIndex].command
                    if cmd.starts(with: "/") {
                        executeCommand(cmd)
                    }
                }
                selectedHistoryIndex = actualIndex
                lastClickIndex = actualIndex
                lastClickTime = now
                showingEasterEgg = false
            }
        }
    }

    func moveSelection(_ delta: Int) {
        guard let current = selectedHistoryIndex else { return }
        let next = current + delta
        if next >= 0 && next < history.count {
            selectedHistoryIndex = next
            showingEasterEgg = (history[next].command == config.commands.blimp)
        }
    }

    func executeCommand(_ cmdStr: String) {
        if isExecuting { return }
        let trimmed = cmdStr.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        showingEasterEgg = false
        activeAppPrompt = nil

        let cmd = config.commands

        if trimmed == cmd.quit {
            isRunning = false
            return
        }

        if trimmed == cmd.help {
            history.append(HistoryItem(command: trimmed, output: getHelpText()))
            selectedHistoryIndex = history.count - 1
            return
        } else if trimmed == cmd.config {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [configURL.path]
            try? process.run()
            history.append(HistoryItem(command: trimmed, output: ["Opened config: \(configURL.path)", "Hot-reloading enabled."]))
            selectedHistoryIndex = history.count - 1
            return
        } else if trimmed == cmd.blimp {
            showingEasterEgg = true
            history.append(HistoryItem(command: trimmed, output: ["Enjoy the flight!"]))
            selectedHistoryIndex = history.count - 1
            return
        } else if trimmed == cmd.ui {
            guard let binURL = UIBridge.executableURL() else {
                history.append(HistoryItem(command: trimmed, output: ["Blimp UI binary not found. Build `Blimp` first or place it alongside `blimp`."]))
                selectedHistoryIndex = history.count - 1
                return
            }

            let task = Process()
            task.executableURL = binURL
            do {
                try task.run()
                history.append(HistoryItem(command: trimmed, output: ["Menu Bar UI launched from \(binURL.path)."]))
            } catch {
                history.append(HistoryItem(command: trimmed, output: ["Failed: \(error)"]))
            }
            selectedHistoryIndex = history.count - 1
            return
        } else if trimmed == cmd.uiQuit {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = [UIBridge.executableName]
            do {
                try task.run()
                history.append(HistoryItem(command: trimmed, output: ["Menu Bar UI dismissed."]))
            } catch {
                history.append(HistoryItem(command: trimmed, output: ["Failed to quit UI."]))
            }
            selectedHistoryIndex = history.count - 1
            return
        } else if trimmed == cmd.uiAutostart {
            guard let binURL = UIBridge.executableURL() else {
                history.append(HistoryItem(command: trimmed, output: ["Blimp UI binary not found. Build `Blimp` first or place it alongside `blimp`."]))
                selectedHistoryIndex = history.count - 1
                return
            }

            let agentsDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents")
            let plistPath = agentsDir.appendingPathComponent("\(UIBridge.launchAgentLabel).plist")

            if FileManager.default.fileExists(atPath: plistPath.path) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                task.arguments = ["unload", plistPath.path]
                try? task.run()
                try? FileManager.default.removeItem(at: plistPath)
                history.append(HistoryItem(command: trimmed, output: ["Autostart DISABLED."]))
            } else {
                let plist = [
                    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
                    "<plist version=\"1.0\">",
                    "<dict>",
                    "    <key>Label</key>",
                    "    <string>\(UIBridge.launchAgentLabel)</string>",
                    "    <key>ProgramArguments</key>",
                    "    <array>",
                    "        <string>\(binURL.path)</string>",
                    "    </array>",
                    "    <key>RunAtLoad</key>",
                    "    <true/>",
                    "    <key>KeepAlive</key>",
                    "    <false/>",
                    "</dict>",
                    "</plist>"
                ].joined(separator: "\n")

                do {
                    if !FileManager.default.fileExists(atPath: agentsDir.path) {
                        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
                    }
                    try plist.write(to: plistPath, atomically: true, encoding: .utf8)
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                    task.arguments = ["load", plistPath.path]
                    try task.run()
                    history.append(HistoryItem(command: trimmed, output: ["Autostart ENABLED."]))
                } catch {
                    history.append(HistoryItem(command: trimmed, output: ["Toggle error: \(error)"]))
                }
            }
            selectedHistoryIndex = history.count - 1
            return
        }

        if trimmed.hasPrefix(cmd.uninstall) {
            let query = String(trimmed.dropFirst(cmd.uninstall.count)).trimmingCharacters(in: .whitespaces)
            let matches = appManager.searchApps(query: query)
            if matches.isEmpty {
                history.append(HistoryItem(command: trimmed, output: ["No apps found for '\(query)'."]))
            } else if matches.count == 1 {
                executeUninstall(app: matches[0])
            } else {
                activeAppPrompt = matches
                history.append(HistoryItem(command: trimmed, output: ["Select app number:"]))
            }
            selectedHistoryIndex = history.count - 1
            return
        }

        let histIndex = history.count
        history.append(HistoryItem(command: trimmed, output: ["Executing..."]))
        selectedHistoryIndex = histIndex
        isExecuting = true

        let targetClean = cmd.clean
        let targetCleanRam = cmd.cleanRam
        let targetCleanCache = cmd.cleanCache
        let targetApps = cmd.apps
        let targetAppsInstalled = cmd.appsInstalled

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var output: [String] = []
            if trimmed == targetClean {
                self?.monitor.freeRAMAction()
                self?.monitor.cleanStorageAction()
                output.append("Cleanup complete.")
            } else if trimmed == targetCleanRam {
                self?.monitor.freeRAMAction()
                output.append("RAM freed.")
            } else if trimmed == targetCleanCache {
                self?.monitor.cleanStorageAction()
                output.append("Caches cleared.")
            } else if trimmed == targetApps {
                if let apps = self?.appManager.listApps(installedOnly: false) {
                    for app in apps { output.append(" - \(app.name)") }
                }
            } else if trimmed == targetAppsInstalled {
                if let apps = self?.appManager.listApps(installedOnly: true) {
                    for app in apps { output.append(" - \(app.name)") }
                }
            } else {
                output.append("Unknown command: \(trimmed)")
            }
            DispatchQueue.main.async {
                self?.history[histIndex].output = output
                self?.isExecuting = false
            }
        }
    }

    func executeUninstall(app: AppInfo) {
        let cmdName = config.commands.uninstall + app.name
        let histIndex = history.count
        history.append(HistoryItem(command: cmdName, output: ["Uninstalling..."]))
        selectedHistoryIndex = histIndex
        isExecuting = true
        activeAppPrompt = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let res = self?.appManager.uninstallApp(app: app) ?? "Error."
            DispatchQueue.main.async {
                self?.history[histIndex].output = res.components(separatedBy: "\n")
                self?.isExecuting = false
            }
        }
    }

    func formatBytes(_ bytes: Double) -> String {
        let gb = bytes / (1024 * 1024 * 1024)
        return String(format: "%.1f GB", gb)
    }

    func drawFrame() {
        var buffer = ""
        buffer += "\u{1B}[?25l\u{1B}[H"

        let loaderStr = isExecuting ? " \(loaderChars[loaderFrame % 4])" : ""
        let leftWidth = max(10, Int(Double(cols) * leftPaneWidthRatio))
        let rightWidth = max(1, cols - leftWidth - 1)

        let suggestion = getSuggestion()
        var suggestionExt = ""
        if !suggestion.isEmpty && suggestion.hasPrefix(currentInput.lowercased()) {
            suggestionExt = String(suggestion.dropFirst(currentInput.count))
        }

        let promptMarker = activeAppPrompt != nil ? "Select Number > " : " > "
        let topBarText = "\(promptMarker)\(currentInput)_\(suggestionExt)"

        buffer += hexToAnsi(config.colors.topBarBg, isBackground: true) + hexToAnsi(config.colors.topBarFg)
        let topStr = topBarText + String(repeating: " ", count: max(0, cols - topBarText.count - 2)) + loaderStr
        if !suggestionExt.isEmpty {
            let cInputStr = "\(promptMarker)\(currentInput)_"
            buffer += cInputStr + hexToAnsi(config.colors.suggestion) + suggestionExt + hexToAnsi(config.colors.topBarFg)
            buffer += String(repeating: " ", count: max(0, cols - cInputStr.count - suggestionExt.count - loaderStr.count)) + loaderStr
        } else {
            buffer += topStr.padding(toLength: cols, withPad: " ", startingAt: 0)
        }

        buffer += "\u{1B}[m\n" + String(repeating: "─", count: cols) + "\n"

        let paneHeight = max(1, rows - 4)
        var leftLines: [String] = []
        for i in (0..<history.count).reversed() {
            let isSelected = i == selectedHistoryIndex
            let prefix = isSelected ? "▶ " : "  "
            var line = prefix + history[i].command
            if line.count > leftWidth { line = String(line.prefix(max(0, leftWidth - 3))) + "..." }
            if isSelected {
                line = "\u{1B}[7m" + line.padding(toLength: leftWidth, withPad: " ", startingAt: 0) + "\u{1B}[m"
            } else {
                line = line.padding(toLength: leftWidth, withPad: " ", startingAt: 0)
            }
            leftLines.append(line)
        }

        var rightLines: [String] = []
        if showingEasterEgg {
            let asciiBlimp = [
                "       _...--=--.._     ",
                " .-.  .-'            '-.",
                "  \\  \\/.'              '.\\",
                "   ) |=-                -=|",
                "  /  /\\'.              .'/",
                " '-'  '-.,_____ _____.-'",
                "         8=[_____]      "
            ]
            let offset = (easterEggFrame / 2) % max(1, rightWidth - 25)
            let pad = String(repeating: " ", count: max(0, offset))
            for line in asciiBlimp { rightLines.append(pad + line) }
        } else if let promptApps = activeAppPrompt {
            rightLines.append("Found multiple apps:")
            for (idx, app) in promptApps.enumerated() {
                rightLines.append("[\(idx + 1)] \(app.name)")
            }
        } else if let sel = selectedHistoryIndex, sel < history.count {
            for text in history[sel].output {
                if text.count > rightWidth {
                    rightLines.append(String(text.prefix(rightWidth)))
                } else {
                    rightLines.append(text)
                }
            }
        }

        for y in 0..<paneHeight {
            let leftLine = y < leftLines.count ? leftLines[y] : String(repeating: " ", count: leftWidth)
            let rightLine = y < rightLines.count ? rightLines[y].padding(toLength: rightWidth, withPad: " ", startingAt: 0) : String(repeating: " ", count: rightWidth)
            buffer += "\(leftLine)\(hexToAnsi(config.colors.historyDivider))│\u{1B}[m\(rightLine)\n"
        }

        func formatProgress(label: String, pct: Double, width: Int = 14, fillChar: String, emptyChar: String, extra: String = "") -> String {
            let filled = Int(pct * Double(width))
            let bar = String(repeating: fillChar, count: max(0, min(width, filled)))
                + String(repeating: emptyChar, count: max(0, width - filled))
            return "\(label) [\(bar)] \(extra)"
        }

        let ramStr = formatProgress(
            label: "RAM",
            pct: monitor.ramUsagePercentage,
            width: 14,
            fillChar: config.misc.barFill,
            emptyChar: config.misc.barEmpty,
            extra: String(format: "%.1f%%", monitor.ramUsagePercentage * 100)
        )
        let storageExtra = "\(formatBytes(monitor.usedStorage)) / \(formatBytes(monitor.totalStorage))"
        let storStr = formatProgress(
            label: "Storage",
            pct: monitor.storageUsagePercentage,
            width: 14,
            fillChar: config.misc.barFill,
            emptyChar: config.misc.barEmpty,
            extra: storageExtra
        )

        buffer += hexToAnsi(config.colors.bottomDivider) + String(repeating: "─", count: cols) + "\u{1B}[m"
        buffer += " \(ramStr)     \(storStr)".padding(toLength: cols, withPad: " ", startingAt: 0)

        print(buffer, terminator: "")
        fflush(stdout)
    }
}

@main
struct BlimpCLI {
    static func main() {
        let app = BlimpCLIApp()
        app.run()
    }
}
