import Foundation
import Darwin
import Combine

public class SystemMonitor: ObservableObject {
    @Published public var totalRAM: Double = 0
    @Published public var usedRAM: Double = 0
    @Published public var freeRAM: Double = 0
    @Published public var ramUsagePercentage: Double = 0
    
    @Published public var totalStorage: Double = 0
    @Published public var usedStorage: Double = 0
    @Published public var freeableStorage: Double = 0
    @Published public var storageUsagePercentage: Double = 0
    
    @Published public var isFreeingRAM = false
    @Published public var isCleaningStorage = false
    
    private var timer: Timer?
    
    public init() {
        updateRAM()
        updateStorage()
        startMonitoring()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateRAM()
        }
    }
    
    public func updateRAM() {
        var size: mach_msg_type_number_t = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64()
        
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = Double(vm_kernel_page_size)
            let inactive = Double(vmStats.inactive_count) * pageSize // Sometimes counted as free, but can be released 
            let free = Double(vmStats.free_count) * pageSize
            
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            let used = total - (free + inactive) // We consider inactive as 'freeable' for user understanding
            
            self.usedRAM = used
            self.freeRAM = free + inactive
            self.totalRAM = total
            
            self.ramUsagePercentage = used / total
        }
    }

    public func updateStorage() {
        let path = NSHomeDirectory()
        let fileURL = URL(fileURLWithPath: path)
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            
            if let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacityForImportantUsage {
                self.totalStorage = Double(total)
                self.usedStorage = Double(total - Int(available))
                self.storageUsagePercentage = self.usedStorage / self.totalStorage
            }
        } catch {
            print(error)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
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

    public func freeRAMAction() {
        guard !isFreeingRAM else { return }
        self.isFreeingRAM = true
        DispatchQueue.global(qos: .userInitiated).async {
            // Memory pressure simulation: allocate and release memory to force macOS to purge inactive pages
            // This works without administrator privileges (no password prompt).
            let gigabyte = 1024 * 1024 * 1024
            let pageSize = Int(vm_kernel_page_size)
            let capacity = gigabyte / MemoryLayout<UInt8>.size
            
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            // Gently "touch" the pages to ensure they are actually allocated by the kernel
            for i in stride(from: 0, to: capacity, by: pageSize) {
                pointer[i] = 0
            }
            
            // Hold it briefly to let the kernel react to the pressure
            Thread.sleep(forTimeInterval: 0.5)
            pointer.deallocate()
            
            DispatchQueue.main.async {
                self.updateRAM()
                self.isFreeingRAM = false
            }
        }
    }
    
    public func cleanStorageAction() {
        guard !isCleaningStorage else { return }
        self.isCleaningStorage = true
        DispatchQueue.global(qos: .userInitiated).async {
            let path = NSHomeDirectory()
            let cachePath = path + "/Library/Caches"
            let logPath = path + "/Library/Logs"
            
            self.clearFolder(folderPath: cachePath)
            self.clearFolder(folderPath: logPath)
            
            DispatchQueue.main.async {
                self.updateStorage()
                self.isCleaningStorage = false
            }
        }
    }
    
    private func clearFolder(folderPath: String) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: folderPath) else { return }
        
        for item in contents {
            let itemPath = folderPath + "/" + item
            do {
                try fileManager.removeItem(atPath: itemPath)
            } catch {
                // Silently ignore permissions and continue deleting other files
                continue
            }
        }
    }

    public func performFullCleanup() {
        freeRAMAction()
        cleanStorageAction()
    }
}
