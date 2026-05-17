import Darwin
import Foundation

/// Boot volume usage via statfs("/"). Reports the "used" figure as Finder shows it,
/// which is total - available (not total - free; APFS reserves free blocks).
final class DiskSampler {
    func sample() -> (percent: Double, usedGB: Double, totalGB: Double) {
        var s = statfs()
        guard statfs("/", &s) == 0, s.f_blocks > 0 else { return (0, 0, 0) }
        let block = UInt64(s.f_bsize)
        let total = UInt64(s.f_blocks) * block
        let avail = UInt64(s.f_bavail) * block
        let used = total > avail ? total - avail : 0
        let usedGB = Double(used) / 1_073_741_824
        let totalGB = Double(total) / 1_073_741_824
        return (Double(used) / Double(total) * 100.0, usedGB, totalGB)
    }
}
