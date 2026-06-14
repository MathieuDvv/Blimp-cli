import Foundation

// MARK: - Config

struct BlimpConfig: Codable {
    struct Colors: Codable {
        var topBarBg: String    = "#1a1a2e"
        var topBarFg: String    = "#e0e0e0"
        var suggestion: String  = "#666688"
        var divider: String     = "#2a2a4a"
        var accent: String      = "#4f8ef7"
    }
    struct Commands: Codable {
        var clean:        String = "/clean"
        var cleanRam:     String = "/clean ram"
        var cleanCache:   String = "/clean cache"
        var apps:         String = "/apps"
        var appsInstalled:String = "/apps installed"
        var uninstall:    String = "/uninstall "
        var snipe:        String = "/snipe"
        var scan:         String = "/scan"
        var top:          String = "/top"
        var brew:         String = "/brew"
        var xcode:        String = "/xcode"
        var trash:        String = "/trash"
        var blimp:        String = "/blimp"
        var ui:           String = "/ui"
        var uiAutostart:  String = "/ui autostart"
        var uiQuit:       String = "/ui quit"
        var config:       String = "/config"
        var help:         String = "/help"
        var quit:         String = "/quit"
    }
    struct Misc: Codable {
        var barFill:  String = "█"
        var barEmpty: String = "░"
    }
    var colors   = Colors()
    var commands = Commands()
    var misc     = Misc()
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colors   = try c.decodeIfPresent(Colors.self,   forKey: .colors)   ?? Colors()
        commands = try c.decodeIfPresent(Commands.self, forKey: .commands) ?? Commands()
        misc     = try c.decodeIfPresent(Misc.self,     forKey: .misc)     ?? Misc()
    }
}

// MARK: - App

class BlimpApp {
    let monitor      = SystemMonitor()
    let appManager   = AppManager()
    let diskAnalyzer = DiskAnalyzer()

    var config = BlimpConfig()
    let configURL: URL
    var lastConfigModTime: Date? = nil

    var isRunning  = true
    var currentInput = ""

    struct HistoryItem { let command: String; var output: [String] }
    var history: [HistoryItem] = []
    var selectedHistoryIndex: Int? = nil

    var isExecuting  = false
    var loaderFrame  = 0
    let loaderChars  = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]

    var rows = 24
    var cols = 80
    let leftPaneRatio = 0.28

    var easterEggFrame = 0
    var showingEasterEgg = false

    var activeAppPrompt: [AppInfo]? = nil
    var lastClickTime  = Date.distantPast
    var lastClickIndex: Int? = nil

    // Snipe mode
    var snipeMode        = false
    var snipeGroups: [FileGroup] = []
    var snipeHighlight   = 0
    var snipeScroll      = 0
    var snipeConfirm     = false
    var snipeScanning    = false

    var baseCommands: [String] {
        let cmd = config.commands
        var cmds = [
            cmd.clean, cmd.cleanRam, cmd.cleanCache,
            cmd.snipe, cmd.scan, cmd.top, cmd.trash,
            cmd.brew,
            cmd.blimp, cmd.config, cmd.help, cmd.quit
        ]
        #if os(macOS)
        cmds += [cmd.apps, cmd.appsInstalled, cmd.uninstall, cmd.xcode,
                 cmd.ui, cmd.uiAutostart, cmd.uiQuit]
        #endif
        return cmds
    }

    // MARK: - Init / Config

    init() {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/blimp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("config.json")
    }

    func checkConfig() {
        if !FileManager.default.fileExists(atPath: configURL.path) { saveConfig() }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path),
              let mod = attrs[.modificationDate] as? Date else { return }
        if lastConfigModTime == nil || mod > lastConfigModTime! {
            if let data = try? Data(contentsOf: configURL),
               let cfg  = try? JSONDecoder().decode(BlimpConfig.self, from: data) { config = cfg }
            lastConfigModTime = mod
        }
    }

    func saveConfig() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) { try? data.write(to: configURL) }
    }

    // MARK: - Help

    func getHelpText() -> [String] {
        let cmd = config.commands
        var pairs: [(String, String)] = [
            (cmd.clean,           "Full system sweep"),
            (cmd.cleanRam,        "Purge inactive RAM"),
            (cmd.cleanCache,      "Wipe caches & logs"),
            (cmd.snipe,           "Smart large-file sniper"),
            (cmd.scan,            "Disk usage breakdown"),
            (cmd.top,             "Top memory processes"),
            (cmd.brew,            "Homebrew cleanup (macOS/Linux)"),
            (cmd.trash,           "Empty Trash"),
            (cmd.config,          "Edit config file"),
            (cmd.help,            "Show this screen"),
            (cmd.quit,            "Exit Blimp"),
        ]
        #if os(macOS)
        pairs += [
            (cmd.xcode,                "Nuke Xcode DerivedData"),
            (cmd.apps,                 "List all apps"),
            (cmd.appsInstalled,        "List user-installed apps"),
            ("\(cmd.uninstall)<name>", "Deep uninstall app"),
            (cmd.ui,                   "Launch Menu Bar UI"),
            (cmd.uiAutostart,          "Toggle UI autostart"),
            (cmd.uiQuit,               "Quit Menu Bar UI"),
        ]
        #endif
        var lines = ["Blimp  ─  System Janitor  [\(Platform.osName)]",
                     String(repeating: "─", count: 46)]
        for (k, v) in pairs {
            lines.append("  " + k.padding(toLength: 24, withPad: " ", startingAt: 0) + v)
        }
        lines.append("")
        lines.append("  Tab/→ autocomplete · ↑↓ navigate · click history")
        return lines
    }

    // MARK: - Run loop

    func run() {
        checkConfig()
        Terminal.enableRawMode()
        defer { Terminal.disableRawMode() }
        history.append(HistoryItem(command: "Welcome to Blimp", output: getHelpText()))
        selectedHistoryIndex = 0
        while isRunning {
            let size = Terminal.getWindowSize()
            rows = size.rows; cols = size.cols
            monitor.loopTick()
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            checkConfig()
            if isExecuting || snipeScanning { loaderFrame += 1 }
            if showingEasterEgg { easterEggFrame += 1 }
            drawFrame()
            if let keys = Terminal.readKey() { processKeys(keys: keys) }
        }
    }

    // MARK: - Key handling

    func processKeys(keys: [UInt8]) {
        if snipeMode {
            processSnipeKeys(keys: keys)
            return
        }
        guard keys.count >= 1 else { return }
        let c = keys[0]
        if keys.count == 1 {
            if c == 127 || c == 8 {
                if !currentInput.isEmpty { currentInput.removeLast() }
            } else if c == 13 || c == 10 {
                #if os(macOS)
                if let apps = activeAppPrompt {
                    if let n = Int(currentInput), n > 0, n <= apps.count {
                        currentInput = ""; activeAppPrompt = nil
                        executeUninstall(app: apps[n - 1])
                    } else { currentInput = "" }
                    return
                }
                #endif
                if currentInput.isEmpty {
                    if let sel = selectedHistoryIndex, sel < history.count {
                        let cmd = history[sel].command
                        if cmd.hasPrefix("/") { executeCommand(cmd) }
                    }
                } else {
                    executeCommand(currentInput); currentInput = ""
                }
            } else if c == 3 { isRunning = false
            } else if c == 9 {
                let s = getSuggestion(); if !s.isEmpty { currentInput = s }
            } else if c >= 32 && c <= 126 {
                currentInput.append(Character(UnicodeScalar(c)))
            } else if c == 27 {
                #if os(macOS)
                if activeAppPrompt != nil { activeAppPrompt = nil; currentInput = ""; return }
                #endif
                isRunning = false
            }
        } else if keys.count > 2 && keys[0] == 27 && keys[1] == 91 {
            if keys.count == 3 {
                if keys[2] == 65 { moveSelection(1) }
                else if keys[2] == 66 { moveSelection(-1) }
                else if keys[2] == 67 {
                    let s = getSuggestion(); if !s.isEmpty { currentInput = s }
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

    func processSnipeKeys(keys: [UInt8]) {
        guard keys.count >= 1 else { return }
        let c = keys[0]
        if keys.count == 1 {
            if c == 27 {
                if snipeConfirm { snipeConfirm = false }
                else { exitSnipeMode() }
            } else if c == 32 && !snipeConfirm {
                if snipeHighlight < snipeGroups.count {
                    snipeGroups[snipeHighlight].isSelected.toggle()
                }
            } else if (c == 13 || c == 10) {
                if snipeConfirm {
                    deleteSelectedGroups()
                    snipeConfirm = false
                } else {
                    let hasSelected = snipeGroups.contains { $0.isSelected }
                    if hasSelected { snipeConfirm = true }
                }
            } else if c == 121 || c == 89 { // y/Y
                if snipeConfirm {
                    deleteSelectedGroups()
                    snipeConfirm = false
                }
            } else if c == 110 || c == 78 { // n/N
                snipeConfirm = false
            } else if c == 97 || c == 65 { // a/A = select all
                let allSelected = snipeGroups.allSatisfy { $0.isSelected }
                for i in snipeGroups.indices { snipeGroups[i].isSelected = !allSelected }
            }
        } else if keys.count > 2 && keys[0] == 27 && keys[1] == 91 {
            if keys.count == 3 {
                if keys[2] == 65 { // Up
                    if snipeHighlight > 0 { snipeHighlight -= 1 }
                    if snipeHighlight < snipeScroll { snipeScroll = snipeHighlight }
                } else if keys[2] == 66 { // Down
                    if snipeHighlight < snipeGroups.count - 1 { snipeHighlight += 1 }
                    let visibleRows = max(1, rows - 5)
                    if snipeHighlight >= snipeScroll + visibleRows { snipeScroll = snipeHighlight - visibleRows + 1 }
                }
            }
        }
    }

    func getSuggestion() -> String {
        guard !currentInput.isEmpty else { return "" }
        if currentInput.hasPrefix(config.commands.uninstall) { return "" }
        for cmd in baseCommands {
            if cmd.hasPrefix(currentInput.lowercased()) { return cmd }
        }
        return ""
    }

    func moveSelection(_ delta: Int) {
        guard let cur = selectedHistoryIndex else { return }
        let next = cur + delta
        if next >= 0 && next < history.count {
            selectedHistoryIndex = next
            showingEasterEgg = (history[next].command == config.commands.blimp)
        }
    }

    func handleMouseClick(x: Int, y: Int) {
        let leftWidth = Int(Double(cols) * leftPaneRatio)
        let startY    = 3
        #if os(macOS)
        if activeAppPrompt != nil {
            let idx = y - startY - 3
            if idx >= 0 && idx < activeAppPrompt!.count {
                let app = activeAppPrompt![idx]
                currentInput = ""; activeAppPrompt = nil
                executeUninstall(app: app); return
            }
        }
        #endif
        if x <= leftWidth && y >= startY && y < rows - 2 {
            let listIdx   = y - startY
            let actualIdx = history.count - 1 - listIdx
            if actualIdx >= 0 && actualIdx < history.count {
                let now = Date()
                if let last = lastClickIndex, last == actualIdx, now.timeIntervalSince(lastClickTime) < 0.4 {
                    let cmd = history[actualIdx].command
                    if cmd.hasPrefix("/") { executeCommand(cmd) }
                }
                selectedHistoryIndex = actualIdx
                lastClickIndex = actualIdx; lastClickTime = now
                showingEasterEgg = false
            }
        }
    }

    // MARK: - Commands

    func executeCommand(_ cmdStr: String) {
        if isExecuting || snipeScanning { return }
        let t = cmdStr.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        showingEasterEgg = false
        #if os(macOS)
        activeAppPrompt = nil
        #endif
        let cmd = config.commands

        if t == cmd.quit { isRunning = false; return }

        if t == cmd.help {
            push(command: t, output: getHelpText()); return
        }
        if t == cmd.config {
            Process.run(url: URL(fileURLWithPath: "/usr/bin/open"), args: [configURL.path])
            push(command: t, output: ["Opened: \(configURL.path)", "Hot-reload enabled."]); return
        }
        if t == cmd.blimp {
            showingEasterEgg = true
            push(command: t, output: ["🪂 Enjoy the flight!"]); return
        }
        #if os(macOS)
        if t == cmd.ui {
            let bin = "/Users/mathieu/Documents/Projects/Others/CleanMyMacLite/.build/release/CleanMyMacLite"
            do {
                try Process().tap { $0.executableURL = URL(fileURLWithPath: bin) }.run()
                push(command: t, output: ["Menu Bar UI launched."])
            } catch { push(command: t, output: ["Failed: \(error)"]) }
            return
        }
        if t == cmd.uiQuit {
            Process.run(url: URL(fileURLWithPath: "/usr/bin/killall"), args: ["CleanMyMacLite"])
            push(command: t, output: ["Menu Bar UI dismissed."]); return
        }
        if t == cmd.uiAutostart { handleUIAutostart(t); return }
        #endif

        if t == cmd.snipe {
            startSnipe(); return
        }

        #if os(macOS)
        if t.hasPrefix(cmd.uninstall) {
            let q = String(t.dropFirst(cmd.uninstall.count)).trimmingCharacters(in: .whitespaces)
            let matches = appManager.searchApps(query: q)
            if matches.isEmpty { push(command: t, output: ["No apps found for '\(q)'."]) }
            else if matches.count == 1 { executeUninstall(app: matches[0]) }
            else { activeAppPrompt = matches; push(command: t, output: ["Select app number:"]) }
            return
        }
        #endif

        let histIdx = history.count
        push(command: t, output: ["Running \(loaderChars[0])"])
        isExecuting = true
        let targetClean      = cmd.clean
        let targetCleanRam   = cmd.cleanRam
        let targetCleanCache = cmd.cleanCache
        let targetApps       = cmd.apps
        let targetAppsInst   = cmd.appsInstalled
        let targetScan       = cmd.scan
        let targetTop        = cmd.top
        let targetBrew       = cmd.brew
        let targetXcode      = cmd.xcode
        let targetTrash      = cmd.trash

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var out: [String] = []
            if t == targetClean {
                self.monitor.freeRAMAction()
                out = ["RAM freed."] + self.monitor.cleanStorageAction()
            } else if t == targetCleanRam {
                self.monitor.freeRAMAction()
                out = ["RAM pressured — inactive pages reclaimed."]
            } else if t == targetCleanCache {
                out = self.monitor.cleanStorageAction()
            } else if t == targetScan {
                let results = self.diskAnalyzer.scanDiskUsage()
                let maxSize = results.first?.size ?? 1
                out = ["Disk Usage  [\(Platform.osName)]", String(repeating: "─", count: 44)]
                for r in results {
                    let bar = self.asciiBar(pct: Double(r.size) / Double(maxSize), width: 12)
                    let sz  = self.monitor.formatBytes(Double(r.size))
                    out.append("  \(r.name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(bar) \(sz)")
                }
            } else if t == targetTop {
                let procs = self.monitor.topProcessesByMemory()
                out = ["Top Processes by RAM [\(Platform.osName)]", String(repeating: "─", count: 44)]
                for (i, p) in procs.enumerated() {
                    out.append("  \(i+1). \(p.name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(String(format: "%.0f MB", p.memMB))")
                }
            } else if t == targetBrew {
                out = ["Homebrew Cleanup"] + self.monitor.brewClean()
            } else if t == targetTrash {
                out = self.monitor.emptyTrash()
            } else {
                #if os(macOS)
                if t == targetApps {
                    out = self.appManager.listApps(installedOnly: false).map { "  \($0.name)  \($0.path.path)" }
                } else if t == targetAppsInst {
                    out = self.appManager.listApps(installedOnly: true).map { "  \($0.name)" }
                } else if t == targetXcode {
                    out = self.monitor.cleanXcode()
                } else {
                    out = ["Unknown command: \(t)", "Type /help for a list."]
                }
                #else
                out = ["Unknown command: \(t)", "Type /help for a list."]
                #endif
            }
            DispatchQueue.main.async {
                self.history[histIdx].output = out
                self.isExecuting = false
            }
        }
    }

    #if os(macOS)
    func executeUninstall(app: AppInfo) {
        let name = config.commands.uninstall + app.name
        let idx  = history.count
        push(command: name, output: ["Uninstalling \(app.name)…"])
        isExecuting = true; activeAppPrompt = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let res = self?.appManager.uninstallApp(app: app) ?? "Error."
            DispatchQueue.main.async {
                self?.history[idx].output = res.components(separatedBy: "\n")
                self?.isExecuting = false
            }
        }
    }

    #endif // os(macOS) for executeUninstall

    func push(command: String, output: [String]) {
        history.append(HistoryItem(command: command, output: output))
        selectedHistoryIndex = history.count - 1
    }

    // MARK: - Snipe mode

    func startSnipe() {
        snipeMode     = true
        snipeGroups   = []
        snipeHighlight = 0
        snipeScroll   = 0
        snipeConfirm  = false
        snipeScanning = true
        push(command: config.commands.snipe, output: ["Scanning…"])
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let groups = self.diskAnalyzer.buildGroups()
            DispatchQueue.main.async {
                self.snipeGroups  = groups
                self.snipeScanning = false
            }
        }
    }

    func exitSnipeMode() {
        snipeMode    = false
        snipeConfirm = false
        snipeGroups  = []
    }

    func deleteSelectedGroups() {
        let fm = FileManager.default
        var deleted: [String] = []
        var totalFreed: Int64 = 0
        for (i, group) in snipeGroups.enumerated() {
            guard group.isSelected else { continue }
            for url in group.items {
                let size = DiskAnalyzer.sizeOfFile(url)
                do {
                    try fm.removeItem(at: url)
                    totalFreed += size
                } catch {
                    #if os(macOS)
                    // Fall back to moving the item to the Trash
                    try? fm.trashItem(at: url, resultingItemURL: nil)
                    #endif
                }
            }
            deleted.append(group.name)
            snipeGroups[i].isSelected = false
        }
        monitor.updateStorage()
        snipeGroups = snipeGroups.filter { !deleted.contains($0.name) }
        if snipeHighlight >= snipeGroups.count { snipeHighlight = max(0, snipeGroups.count - 1) }
        let freed = monitor.formatBytes(Double(totalFreed))
        push(command: "/snipe delete", output: ["Deleted \(deleted.count) group(s), freed ~\(freed)."] + deleted.map { "  \($0)" })
    }

    // MARK: - UI Autostart (macOS-only)

    #if os(macOS)
    func handleUIAutostart(_ t: String) {
        let bin = "/Users/mathieu/Documents/Projects/Others/CleanMyMacLite/.build/release/CleanMyMacLite"
        let agentsDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents")
        let plistPath = agentsDir.appendingPathComponent("com.mathieu.blimp.ui.plist")
        if FileManager.default.fileExists(atPath: plistPath.path) {
            Process.run(url: URL(fileURLWithPath: "/bin/launchctl"), args: ["unload", plistPath.path])
            try? FileManager.default.removeItem(at: plistPath)
            push(command: t, output: ["Autostart DISABLED."])
        } else {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>com.mathieu.blimp.ui</string>
              <key>ProgramArguments</key><array><string>\(bin)</string></array>
              <key>RunAtLoad</key><true/>
              <key>KeepAlive</key><false/>
            </dict></plist>
            """
            do {
                try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
                try plist.write(to: plistPath, atomically: true, encoding: .utf8)
                Process.run(url: URL(fileURLWithPath: "/bin/launchctl"), args: ["load", plistPath.path])
                push(command: t, output: ["Autostart ENABLED."])
            } catch { push(command: t, output: ["Error: \(error)"]) }
        }
    }

    #endif // os(macOS) for handleUIAutostart

    // MARK: - Drawing

    func drawFrame() {
        var buf = "\u{1B}[?25l\u{1B}[H"
        if snipeMode {
            buf += drawSnipeFrame()
        } else {
            buf += drawNormalFrame()
        }
        buf += drawStatusBar()
        print(buf, terminator: "")
        fflush(stdout)
    }

    func drawNormalFrame() -> String {
        var buf = ""
        let leftW = max(10, Int(Double(cols) * leftPaneRatio))
        let rightW = max(1, cols - leftW - 1)
        let suggestion    = getSuggestion()
        var suggestionExt = ""
        if !suggestion.isEmpty && suggestion.hasPrefix(currentInput.lowercased()) {
            suggestionExt = String(suggestion.dropFirst(currentInput.count))
        }
        let loader    = isExecuting ? " \(loaderChars[loaderFrame % loaderChars.count])" : ""
        #if os(macOS)
        let marker    = activeAppPrompt != nil ? " Select # > " : " > "
        #else
        let marker    = " > "
        #endif
        let inputLine = "\(marker)\(currentInput)_"

        buf += ansi(hex: config.colors.topBarBg, bg: true) + ansi(hex: config.colors.topBarFg)
        if !suggestionExt.isEmpty {
            buf += inputLine + ansi(hex: config.colors.suggestion) + suggestionExt + ansi(hex: config.colors.topBarFg)
            let pad = max(0, cols - inputLine.count - suggestionExt.count - loader.count)
            buf += String(repeating: " ", count: pad) + loader
        } else {
            let line = (inputLine + loader).padding(toLength: cols, withPad: " ", startingAt: 0)
            buf += line
        }
        buf += "\u{1B}[m\n"
        buf += ansi(hex: config.colors.accent) + String(repeating: "─", count: cols) + "\u{1B}[m\n"

        let paneH = max(1, rows - 4)

        // Left pane: history list
        var leftLines: [String] = []
        for i in (0..<history.count).reversed() {
            let selected = i == selectedHistoryIndex
            let prefix   = selected ? "▶ " : "  "
            var line     = prefix + history[i].command
            if line.count > leftW { line = String(line.prefix(max(0, leftW - 1))) }
            if selected { line = "\u{1B}[7m" + line.padding(toLength: leftW, withPad: " ", startingAt: 0) + "\u{1B}[m" }
            else         { line = line.padding(toLength: leftW, withPad: " ", startingAt: 0) }
            leftLines.append(line)
        }

        // Right pane: output / easter egg / app prompt
        var rightLines: [String] = []
        if showingEasterEgg {
            let art = [
                "       _...--=--.._    ",
                " .-.  .-'            '-.",
                "  \\  \\/.'             '.\\",
                "   ) |=-             -=| ",
                "  /  /\\'.           .'/  ",
                " '-'  '-.,______.-'     ",
                "          8=[___]       "
            ]
            let offset = (easterEggFrame / 2) % max(1, rightW - 26)
            let pad    = String(repeating: " ", count: max(0, offset))
            for ln in art { rightLines.append(pad + ln) }
        } else {
            var usedAppsPrompt = false
            #if os(macOS)
            if let apps = activeAppPrompt {
                rightLines.append("Multiple matches — pick one:")
                rightLines.append(String(repeating: "─", count: min(rightW, 30)))
                for (i, a) in apps.enumerated() { rightLines.append("  [\(i+1)] \(a.name)") }
                usedAppsPrompt = true
            }
            #endif
            if !usedAppsPrompt, let sel = selectedHistoryIndex, sel < history.count {
                for ln in history[sel].output {
                    rightLines.append(ln.count > rightW ? String(ln.prefix(rightW)) : ln)
                }
            }
        }

        let div = ansi(hex: config.colors.divider) + "│" + "\u{1B}[m"
        for y in 0..<paneH {
            let l = y < leftLines.count  ? leftLines[y]  : String(repeating: " ", count: leftW)
            let r = y < rightLines.count ? rightLines[y].padding(toLength: rightW, withPad: " ", startingAt: 0)
                                         : String(repeating: " ", count: rightW)
            buf += "\(l)\(div)\(r)\n"
        }
        return buf
    }

    func drawSnipeFrame() -> String {
        var buf = ""
        let leftW  = max(20, Int(Double(cols) * 0.38))
        let rightW = max(1, cols - leftW - 1)
        let paneH  = max(1, rows - 4)
        let div    = ansi(hex: config.colors.divider) + "│" + "\u{1B}[m"

        // Top bar: snipe controls
        buf += ansi(hex: "#1a2a1a", bg: true) + ansi(hex: "#88ff88")
        let selectedCount = snipeGroups.filter { $0.isSelected }.count
        let selectedSize  = snipeGroups.filter { $0.isSelected }.reduce(0) { $0 + $1.totalSize }
        let topMsg: String
        if snipeConfirm {
            let sz = monitor.formatBytes(Double(selectedSize))
            topMsg = " ⚠  DELETE \(selectedCount) group(s) (\(sz))? [Y]es / [N]o / Esc  "
        } else if snipeScanning {
            topMsg = " \(loaderChars[loaderFrame % loaderChars.count]) SNIPER — Scanning filesystem…  "
        } else if selectedCount > 0 {
            let sz = monitor.formatBytes(Double(selectedSize))
            topMsg = " SNIPER — \(selectedCount) selected (\(sz))  SPACE:toggle  ENTER:delete  A:all  ESC:back"
        } else {
            topMsg = " SNIPER — \(snipeGroups.count) groups  ↑↓:navigate  SPACE:select  A:all  ESC:back"
        }
        buf += topMsg.padding(toLength: cols, withPad: " ", startingAt: 0)
        buf += "\u{1B}[m\n"
        buf += ansi(hex: "#2a4a2a") + String(repeating: "─", count: cols) + "\u{1B}[m\n"

        // Left: groups list
        var leftLines: [String] = []
        for (i, group) in snipeGroups.enumerated() {
            let check   = group.isSelected ? "[x]" : "[ ]"
            let tag     = "[\(group.tag)]"
            let sz      = monitor.formatBytes(Double(group.totalSize))
            let isHl    = i == snipeHighlight
            let nameTrunc = group.name.count > (leftW - 14) ? String(group.name.prefix(leftW - 14)) : group.name
            var line    = " \(check) \(tag) \(nameTrunc)"
            let sizeStr = "  \(sz)"
            let totalLen = line.count + sizeStr.count
            if totalLen < leftW { line += String(repeating: " ", count: leftW - totalLen) + sizeStr }
            else { line = line.padding(toLength: leftW - sizeStr.count, withPad: " ", startingAt: 0) + sizeStr }
            if isHl  { line = "\u{1B}[7m" + line + "\u{1B}[m" }
            else if group.isSelected { line = "\u{1B}[32m" + line + "\u{1B}[m" }
            leftLines.append(line)
        }

        // Right: items in highlighted group
        var rightLines: [String] = []
        if snipeScanning {
            rightLines = ["Scanning…", "", "This may take a moment.", "Large directories (Xcode,", "Simulators) take longest."]
        } else if snipeGroups.isEmpty {
            rightLines = ["No large junk found!", "", "Your system looks clean."]
        } else if snipeHighlight < snipeGroups.count {
            let group = snipeGroups[snipeHighlight]
            rightLines.append("\u{1B}[1m\(group.name)\u{1B}[m")
            rightLines.append(group.description)
            rightLines.append(String(repeating: "─", count: min(rightW, 36)))
            for item in group.items {
                let name = item.lastPathComponent
                let size = DiskAnalyzer.sizeOfFile(item)
                let sz   = size > 0 ? monitor.formatBytes(Double(size)) : ""
                let line = "  \(name)\(sz.isEmpty ? "" : "  \(sz)")"
                rightLines.append(line.count > rightW ? String(line.prefix(rightW)) : line)
            }
        }

        for y in 0..<paneH {
            let scrolledY = y + snipeScroll
            let l = scrolledY < leftLines.count  ? leftLines[scrolledY]  : String(repeating: " ", count: leftW)
            let r = y < rightLines.count ? rightLines[y].padding(toLength: rightW, withPad: " ", startingAt: 0)
                                         : String(repeating: " ", count: rightW)
            buf += "\(l)\(div)\(r)\n"
        }
        return buf
    }

    func drawStatusBar() -> String {
        var buf = ""
        let fill  = config.misc.barFill
        let empty = config.misc.barEmpty
        let cpuPct  = monitor.cpuUsagePercentage
        let ramPct  = monitor.ramUsagePercentage
        let storagePct = monitor.storageUsagePercentage

        let cpuBar  = coloredBar(pct: cpuPct,     width: 10, fill: fill, empty: empty)
        let ramBar  = coloredBar(pct: ramPct,     width: 10, fill: fill, empty: empty)
        let stoBar  = coloredBar(pct: storagePct, width: 10, fill: fill, empty: empty)
        let usedGB  = String(format: "%.0f", monitor.usedStorage / (1024*1024*1024))
        let totalGB = String(format: "%.0f", monitor.totalStorage / (1024*1024*1024))

        let statusLine = " CPU\(cpuBar)\(String(format: "%2.0f%%", cpuPct * 100))  RAM\(ramBar)\(String(format: "%2.0f%%", ramPct * 100))  SSD\(stoBar)\(usedGB)/\(totalGB)GB"

        buf += ansi(hex: config.colors.accent) + String(repeating: "─", count: cols) + "\u{1B}[m\n"
        buf += statusLine.padding(toLength: cols, withPad: " ", startingAt: 0)
        return buf
    }

    // MARK: - Helpers

    func coloredBar(pct: Double, width: Int, fill: String, empty: String) -> String {
        let filled = max(0, min(width, Int(pct * Double(width))))
        let bar    = String(repeating: fill, count: filled) + String(repeating: empty, count: width - filled)
        let color: String
        if pct < 0.5      { color = "\u{1B}[32m" }
        else if pct < 0.8 { color = "\u{1B}[33m" }
        else               { color = "\u{1B}[31m" }
        return "\(color)[\(bar)]\u{1B}[m"
    }

    func asciiBar(pct: Double, width: Int) -> String {
        let f = config.misc.barFill; let e = config.misc.barEmpty
        let n = max(0, min(width, Int(pct * Double(width))))
        return "[" + String(repeating: f, count: n) + String(repeating: e, count: width - n) + "]"
    }

    func ansi(hex: String, bg: Bool = false) -> String {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let rgb = Int(h, radix: 16) else { return "" }
        let r = (rgb >> 16) & 0xFF; let g = (rgb >> 8) & 0xFF; let b = rgb & 0xFF
        return "\u{1B}[\(bg ? 48 : 38);2;\(r);\(g);\(b)m"
    }
}

// MARK: - Process helper

extension Process {
    @discardableResult
    func tap(_ f: (Process) -> Void) -> Process { f(self); return self }

    static func run(url: URL, args: [String]) {
        let p = Process()
        p.executableURL = url
        p.arguments     = args
        try? p.run()
    }
}

// MARK: - Entry point

@main
struct Blimp {
    static func main() {
        let app = BlimpApp()
        app.run()
    }
}
