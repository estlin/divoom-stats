import Foundation

struct Stats {
    var cpuPercent: Double = 0     // 0..100
    var cpuTempC: Double? = nil    // nil until macmon samples
    var gpuPercent: Double = 0
    var gpuTempC: Double? = nil
    var ramPercent: Double = 0
    var ramUsedGB: Double = 0
    var ramTotalGB: Double = 0
    var diskPercent: Double = 0
    var diskUsedGB: Double = 0
    var diskTotalGB: Double = 0
}
