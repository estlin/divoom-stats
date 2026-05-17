import Foundation

/// Long-running `macmon pipe -i <ms>` subprocess. Parses one JSON object per line.
/// Exposes the most recent sample (or nil if macmon hasn't reported yet / isn't installed).
final class MacmonSampler {
    struct Sample {
        let cpuTempC: Double?
        let gpuTempC: Double?
        let gpuPercent: Double?    // 0..100
    }

    private let intervalMs: Int
    private let macmonPath: String
    private var task: Process?
    private let lock = NSLock()
    private var latest: Sample? = nil

    init(intervalMs: Int = 2000) {
        self.intervalMs = intervalMs
        self.macmonPath = MacmonSampler.locate() ?? "/opt/homebrew/bin/macmon"
    }

    private static func locate() -> String? {
        // Prefer the bundled binary so a distributed .app doesn't depend on
        // Homebrew being installed on the user's machine. Fall back to system
        // Homebrew paths for development runs from the command line.
        var candidates: [String] = []
        if let bundled = Bundle.main.path(forResource: "macmon", ofType: nil) {
            candidates.append(bundled)
        }
        candidates += ["/opt/homebrew/bin/macmon", "/usr/local/bin/macmon"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: macmonPath) }

    func current() -> Sample? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    func start() {
        guard isAvailable, task == nil else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: macmonPath)
        proc.arguments = ["pipe", "-i", String(intervalMs)]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            // macmon emits one JSON object per line.
            data.split(separator: 0x0a).forEach { line in
                self.ingest(Data(line))
            }
        }

        do {
            try proc.run()
            task = proc
        } catch {
            fputs("macmon failed to launch: \(error)\n", stderr)
        }
    }

    func stop() {
        task?.terminate()
        task = nil
    }

    private func ingest(_ jsonLine: Data) {
        guard
            let obj = try? JSONSerialization.jsonObject(with: jsonLine) as? [String: Any]
        else { return }
        let temp = obj["temp"] as? [String: Any]
        let cpuTemp = temp?["cpu_temp_avg"] as? Double
        let gpuTemp = temp?["gpu_temp_avg"] as? Double
        // gpu_usage is [freq_mhz, ratio_0_to_1]
        var gpuPct: Double? = nil
        if let arr = obj["gpu_usage"] as? [Any], arr.count >= 2, let ratio = arr[1] as? Double {
            gpuPct = ratio * 100.0
        }
        let s = Sample(cpuTempC: cpuTemp, gpuTempC: gpuTemp, gpuPercent: gpuPct)
        lock.lock(); latest = s; lock.unlock()
    }
}
