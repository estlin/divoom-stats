import Darwin

/// Memory usage matching Activity Monitor's notion of "used":
/// physical - (free + speculative) - (purgeable + external).
final class MemorySampler {
    private let pageSize: UInt64 = {
        var sz: vm_size_t = 0
        host_page_size(mach_host_self(), &sz)
        return UInt64(sz)
    }()

    private let totalBytes: UInt64 = {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        return size
    }()

    func sample() -> (percent: Double, usedGB: Double, totalGB: Double) {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS, totalBytes > 0 else { return (0, 0, 0) }

        let free = UInt64(info.free_count) * pageSize
        let spec = UInt64(info.speculative_count) * pageSize
        let purgeable = UInt64(info.purgeable_count) * pageSize
        let external = UInt64(info.external_page_count) * pageSize

        let availableForApps = free &+ spec &+ purgeable &+ external
        let used = totalBytes > availableForApps ? totalBytes &- availableForApps : 0

        let usedGB = Double(used) / 1_073_741_824
        let totalGB = Double(totalBytes) / 1_073_741_824
        let percent = Double(used) / Double(totalBytes) * 100.0
        return (percent, usedGB, totalGB)
    }
}
