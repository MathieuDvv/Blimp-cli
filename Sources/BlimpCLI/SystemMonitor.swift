import Foundation
import Darwin

class SystemMonitor: @unchecked Sendable {
    var totalRAM: Double = 0
    var usedRAM: Double = 0
    var freeRAM: Double = 0
    var ramUsagePercentage: Double = 0

    var totalStorage: Double = 0
    var usedStorage: Double = 0
    var freeableStorage: Double = 0
    var storageUsagePercentage: Double = 0

    var isFreeingRAM = false
    var isCleaningStorage = false

    private var lastRAMUpdate = Date.distantPast
    private var lastStorageUpdate = Date.distantPast

    init() {
        updateRAM(force: true)
        updateStorage(force: true)
    }

    func loopTick() {
        let now = Date()
        if now.timeIntervalSince(lastRAMUpdate) > 2.0 {
            updateRAM(force: true)
        }
        if now.timeIntervalSince(lastStorageUpdate) > 10.0 {
            updateStorage(force: true)
        }
    }

    func updateRAM(force: Bool = false) {
        lastRAMUpdate = Date()
        var size: mach_msg_type_number_t = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64()

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = Double(getpagesize())
            let inactive = Double(vmStats.inactive_count) * pageSize
            let free = Double(vmStats.free_count) * pageSize

            let total = Double(ProcessInfo.processInfo.physicalMemory)
            let used = total - (free + inactive)

            self.usedRAM = used
            self.freeRAM = free + inactive
            self.totalRAM = total
            self.ramUsagePercentage = used / total
        }
    }

    func updateStorage(force: Bool = false) {
        lastStorageUpdate = Date()
        let path = NSHomeDirectory()
        let fileURL = URL(fileURLWithPath: path)
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            if let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacityForImportantUsage {
                self.totalStorage = Double(total)
                self.usedStorage = Double(total - Int(available))
                self.storageUsagePercentage = self.usedStorage / self.totalStorage
            }
        } catch {}

        DispatchQueue.global(qos: .background).async {
            let cachePath = path + "/Library/Caches"
            let logPath = path + "/Library/Logs"
            let size = self.folderSize(folderPath: cachePath) + self.folderSize(folderPath: logPath)
            DispatchQueue.main.async {
                self.freeableStorage = Double(size)
            }
        }
    }

    private func folderSize(folderPath: String) -> Int64 {
        let fileManager = FileManager.default
        var folderSize: Int64 = 0
        if let enumerator = fileManager.enumerator(atPath: folderPath) {
            for file in enumerator {
                if let fileName = file as? String {
                    let filePath = folderPath + "/" + fileName
                    if let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                       let fileSize = attributes[.size] as? Int64 {
                        folderSize += fileSize
                    }
                }
            }
        }
        return folderSize
    }

    func freeRAMAction() {
        self.isFreeingRAM = true
        let gigabyte = 1024 * 1024 * 1024
        let pageSize = Int(getpagesize())
        let capacity = gigabyte / MemoryLayout<UInt8>.size
        let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        for i in stride(from: 0, to: capacity, by: pageSize) {
            pointer[i] = 0
        }
        Thread.sleep(forTimeInterval: 0.5)
        pointer.deallocate()
        self.isFreeingRAM = false
        self.updateRAM(force: true)
    }

    func cleanStorageAction() {
        self.isCleaningStorage = true
        let path = NSHomeDirectory()
        let cachePath = path + "/Library/Caches"
        let logPath = path + "/Library/Logs"
        self.clearFolder(folderPath: cachePath)
        self.clearFolder(folderPath: logPath)
        self.isCleaningStorage = false
        self.updateStorage(force: true)
    }

    private func clearFolder(folderPath: String) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: folderPath) else { return }
        for item in contents {
            let itemPath = folderPath + "/" + item
            do {
                try fileManager.removeItem(atPath: itemPath)
            } catch {}
        }
    }
}
