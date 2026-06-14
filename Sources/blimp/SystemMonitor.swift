import Foundation

// RAM, CPU, and Storage monitoring — fully cross-platform.
// macOS:   Darwin mach kernel APIs
// Linux:   /proc/meminfo  +  /proc/stat
// Windows: WinSDK GlobalMemoryStatusEx + GetSystemTimes + GetDiskFreeSpaceExW

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

class SystemMonitor: @unchecked Sendable {

    // MARK: - Public state

    var totalRAM: Double = 0
    var usedRAM:  Double = 0
    var freeRAM:  Double = 0
    var ramUsagePercentage: Double = 0

    var totalStorage:         Double = 0
    var usedStorage:          Double = 0
    var freeableStorage:      Double = 0
    var storageUsagePercentage: Double = 0

    var cpuUsagePercentage: Double = 0

    // MARK: - Private tracking

    #if os(macOS)
    private var prevCPUTicks: (UInt32, UInt32, UInt32, UInt32)? = nil
    #elseif os(Linux)
    private var prevCPUStat: (total: UInt64, idle: UInt64)? = nil
    #elseif os(Windows)
    private var prevCPUIdle:   UInt64 = 0
    private var prevCPUKernel: UInt64 = 0
    private var prevCPUUser:   UInt64 = 0
    #endif

    private var lastRAMUpdate     = Date.distantPast
    private var lastStorageUpdate = Date.distantPast
    private var lastCPUUpdate     = Date.distantPast

    init() {
        updateRAM(); updateStorage(); updateCPU(); updateCPU()
    }

    func loopTick() {
        let now = Date()
        if now.timeIntervalSince(lastRAMUpdate)     > 2.0  { updateRAM() }
        if now.timeIntervalSince(lastStorageUpdate) > 10.0 { updateStorage() }
        if now.timeIntervalSince(lastCPUUpdate)     > 1.0  { updateCPU() }
    }

    // MARK: - RAM

    func updateRAM() {
        lastRAMUpdate = Date()
        #if os(macOS)
        updateRAMDarwin()
        #elseif os(Linux)
        updateRAMLinux()
        #elseif os(Windows)
        updateRAMWindows()
        #endif
    }

    #if os(macOS)
    private func updateRAMDarwin() {
        var size  = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()
        let kr    = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let page  = Double(getpagesize())
        totalRAM  = Double(ProcessInfo.processInfo.physicalMemory)
        freeRAM   = (Double(stats.free_count) + Double(stats.inactive_count)) * page
        usedRAM   = totalRAM - freeRAM
        ramUsagePercentage = usedRAM / totalRAM
    }
    #elseif os(Linux)
    private func updateRAMLinux() {
        guard let raw = try? String(contentsOfFile: "/proc/meminfo", encoding: .utf8) else { return }
        var total: Double = 0; var avail: Double = 0
        for line in raw.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let val = Double(parts[1].trimmingCharacters(in: .whitespaces)
                                     .replacingOccurrences(of: " kB", with: "")) ?? 0
            if key == "MemTotal"     { total = val * 1024 }
            if key == "MemAvailable" { avail = val * 1024 }
        }
        totalRAM           = total
        freeRAM            = avail
        usedRAM            = total - avail
        ramUsagePercentage = total > 0 ? usedRAM / total : 0
    }
    #elseif os(Windows)
    private func updateRAMWindows() {
        var status = MEMORYSTATUSEX()
        status.dwLength = DWORD(MemoryLayout<MEMORYSTATUSEX>.size)
        GlobalMemoryStatusEx(&status)
        totalRAM           = Double(status.ullTotalPhys)
        freeRAM            = Double(status.ullAvailPhys)
        usedRAM            = totalRAM - freeRAM
        ramUsagePercentage = totalRAM > 0 ? usedRAM / totalRAM : 0
    }
    #endif

    // MARK: - CPU

    func updateCPU() {
        lastCPUUpdate = Date()
        #if os(macOS)
        updateCPUDarwin()
        #elseif os(Linux)
        updateCPULinux()
        #elseif os(Windows)
        updateCPUWindows()
        #endif
    }

    #if os(macOS)
    private func updateCPUDarwin() {
        var info  = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr    = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let t = info.cpu_ticks
        if let prev = prevCPUTicks {
            let user = Double(t.0) - Double(prev.0)
            let sys  = Double(t.1) - Double(prev.1)
            let idle = Double(t.2) - Double(prev.2)
            let nice = Double(t.3) - Double(prev.3)
            let tot  = user + sys + idle + nice
            if tot > 0 { cpuUsagePercentage = (user + sys + nice) / tot }
        }
        prevCPUTicks = t
    }
    #elseif os(Linux)
    private func updateCPULinux() {
        guard let raw   = try? String(contentsOfFile: "/proc/stat", encoding: .utf8) else { return }
        let first = raw.components(separatedBy: "\n").first ?? ""
        let vals  = first.split(separator: " ", omittingEmptySubsequences: true).dropFirst().compactMap { UInt64($0) }
        guard vals.count >= 4 else { return }
        let idle  = vals[3]
        let total = vals.reduce(0, +)
        if let prev = prevCPUStat {
            let dt = Double(total - prev.total)
            let di = Double(idle  - prev.idle)
            if dt > 0 { cpuUsagePercentage = (dt - di) / dt }
        }
        prevCPUStat = (total: total, idle: idle)
    }
    #elseif os(Windows)
    private func updateCPUWindows() {
        var idle = FILETIME(); var kernel = FILETIME(); var user = FILETIME()
        GetSystemTimes(&idle, &kernel, &user)
        let i = fileTimeToUInt64(idle);   let k = fileTimeToUInt64(kernel); let u = fileTimeToUInt64(user)
        let dIdle = Double(i - prevCPUIdle)
        let dSys  = Double(k - prevCPUKernel)
        let dUser = Double(u - prevCPUUser)
        let total = dSys + dUser
        if total > 0 { cpuUsagePercentage = (total - dIdle) / total }
        prevCPUIdle = i; prevCPUKernel = k; prevCPUUser = u
    }
    private func fileTimeToUInt64(_ ft: FILETIME) -> UInt64 {
        UInt64(ft.dwHighDateTime) << 32 | UInt64(ft.dwLowDateTime)
    }
    #endif

    // MARK: - Storage

    func updateStorage() {
        lastStorageUpdate = Date()
        let url = Platform.home
        do {
            #if os(macOS)
            let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
            let v = try url.resourceValues(forKeys: keys)
            if let total = v.volumeTotalCapacity, let avail = v.volumeAvailableCapacityForImportantUsage {
                totalStorage           = Double(total)
                usedStorage            = Double(total - Int(avail))
                storageUsagePercentage = totalStorage > 0 ? usedStorage / totalStorage : 0
            }
            #else
            let keys: Set<URLResourceKey> = [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]
            let v = try url.resourceValues(forKeys: keys)
            if let total = v.volumeTotalCapacity, let avail = v.volumeAvailableCapacity {
                totalStorage           = Double(total)
                usedStorage            = Double(total) - Double(avail)
                storageUsagePercentage = totalStorage > 0 ? usedStorage / totalStorage : 0
            }
            #endif
        } catch {}

        DispatchQueue.global(qos: .background).async {
            let size = Self.dirSize(Platform.cache.path) + Self.dirSize(Platform.logs.path)
            DispatchQueue.main.async { self.freeableStorage = Double(size) }
        }
    }

    // MARK: - Top processes (cross-platform)

    func topProcessesByMemory() -> [(name: String, memMB: Double)] {
        #if os(Windows)
        let exe  = "C:\\Windows\\System32\\tasklist.exe"
        let args = ["/FO", "CSV", "/NH"]
        #else
        let exe  = "/bin/ps"
        let args = ["aux"]
        #endif
        let task = Process()
        task.executableURL = URL(fileURLWithPath: exe)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe; task.standardError = Pipe()
        guard (try? task.run()) != nil else { return [] }
        task.waitUntilExit()
        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        #if os(Windows)
        // tasklist CSV: "name","pid","session","#","mem usage"
        var results: [(String, Double)] = []
        for line in raw.components(separatedBy: "\n").filter({ !$0.isEmpty }) {
            let cols = line.split(separator: "\"").filter { $0 != "," }
            guard cols.count >= 5 else { continue }
            let name = String(cols[0])
            let memStr = String(cols[4]).replacingOccurrences(of: " K", with: "")
                                        .replacingOccurrences(of: ",", with: "")
                                        .trimmingCharacters(in: .whitespaces)
            if let kb = Double(memStr) { results.append((name, kb / 1024)) }
        }
        return results.sorted { $0.1 > $1.1 }.prefix(6).map { $0 }
        #else
        var results: [(String, Double)] = []
        for line in raw.components(separatedBy: "\n").dropFirst() {
            let parts = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
            guard parts.count >= 11, let rss = Double(parts[5]) else { continue }
            let name = String(parts[10].split(separator: "/").last ?? parts[10])
            results.append((name, rss / 1024.0))
        }
        return results.sorted { $0.1 > $1.1 }.prefix(6).map { $0 }
        #endif
    }

    // MARK: - Clean actions

    func freeRAMAction() {
        #if os(Windows)
        let pageSize = 4096
        #elseif os(macOS)
        let pageSize = Int(getpagesize())
        #else
        let pageSize = Int(getpagesize())
        #endif
        let capacity = 1024 * 1024 * 1024 / MemoryLayout<UInt8>.size
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        for i in stride(from: 0, to: capacity, by: pageSize) { ptr[i] = 0 }
        Thread.sleep(forTimeInterval: 0.3)
        ptr.deallocate()
        updateRAM()
    }

    func cleanStorageAction() -> [String] {
        var cleaned: [String] = []
        let targets: [(String, URL)] = platformCleanTargets()
        for (label, url) in targets {
            let before = Self.dirSize(url.path)
            clearFolder(url.path)
            let freed = before - Self.dirSize(url.path)
            if freed > 0 { cleaned.append("  \(label): freed \(formatBytes(Double(freed)))") }
        }
        updateStorage()
        return cleaned.isEmpty ? ["Nothing to clean."] : cleaned
    }

    private func platformCleanTargets() -> [(String, URL)] {
        #if os(macOS)
        return [
            ("Caches", Platform.cache),
            ("Logs",   Platform.logs),
        ]
        #elseif os(Linux)
        return [
            ("~/.cache", Platform.cache),
            ("Temp",     Platform.temp),
        ]
        #elseif os(Windows)
        return [
            ("Temp",           Platform.temp),
            ("LocalAppData\\Temp", Platform.cache.appendingPathComponent("Temp")),
        ]
        #else
        return [("Cache", Platform.cache)]
        #endif
    }

    func emptyTrash() -> [String] {
        let path = Platform.trash.path
        let before = Self.dirSize(path)
        clearFolder(path)
        let freed = before - Self.dirSize(path)
        updateStorage()
        return ["Trash emptied: freed \(formatBytes(Double(freed)))"]
    }

    func brewClean() -> [String] {
        #if os(Windows)
        return ["Homebrew not available on Windows."]
        #else
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["brew"]
        let pipe = Pipe(); which.standardOutput = pipe; which.standardError = Pipe()
        try? which.run(); which.waitUntilExit()
        let brewPath = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !brewPath.isEmpty else { return ["Homebrew not found."] }
        let clean = Process()
        clean.executableURL = URL(fileURLWithPath: brewPath)
        clean.arguments = ["cleanup", "--prune=all"]
        let out = Pipe(); clean.standardOutput = out; clean.standardError = out
        try? clean.run(); clean.waitUntilExit()
        let result = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        updateStorage()
        let lines = result.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.isEmpty ? ["Homebrew cache already clean."] : lines
        #endif
    }

    #if os(macOS)
    func cleanXcode() -> [String] {
        let path = Platform.home.appendingPathComponent("Library/Developer/Xcode/DerivedData").path
        let before = DiskAnalyzer.sizeOfDir(path)
        clearFolder(path)
        let freed = before - DiskAnalyzer.sizeOfDir(path)
        updateStorage()
        return ["Xcode DerivedData: freed \(formatBytes(Double(freed)))"]
    }
    #endif

    // MARK: - Helpers

    private func clearFolder(_ path: String) {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }
        for item in items { try? FileManager.default.removeItem(atPath: path + "/" + item) }
    }

    static func dirSize(_ path: String) -> Int64 {
        let fm = FileManager.default; var total: Int64 = 0
        guard let e = fm.enumerator(atPath: path) else { return 0 }
        for case let f as String in e {
            if let attr = try? fm.attributesOfItem(atPath: path + "/" + f),
               let s    = attr[.size] as? Int64 { total += s }
        }
        return total
    }

    func formatBytes(_ b: Double) -> String {
        switch b {
        case ..<1024:             return String(format: "%.0f B",  b)
        case ..<(1024*1024):      return String(format: "%.1f KB", b / 1024)
        case ..<(1024*1024*1024): return String(format: "%.1f MB", b / (1024*1024))
        default:                  return String(format: "%.2f GB", b / (1024*1024*1024))
        }
    }
}
