import Darwin

/// CPU usage via Mach host_statistics. Tracks delta between samples.
final class CPUSampler {
    private var prevUser: UInt32 = 0
    private var prevSystem: UInt32 = 0
    private var prevIdle: UInt32 = 0
    private var prevNice: UInt32 = 0
    private var primed = false

    func sample() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }

        let user = info.cpu_ticks.0
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3

        defer {
            prevUser = user; prevSystem = system; prevIdle = idle; prevNice = nice
            primed = true
        }
        guard primed else { return 0 }

        let dUser = Double(user &- prevUser)
        let dSystem = Double(system &- prevSystem)
        let dIdle = Double(idle &- prevIdle)
        let dNice = Double(nice &- prevNice)
        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return 0 }
        return (dUser + dSystem + dNice) / total * 100.0
    }
}
