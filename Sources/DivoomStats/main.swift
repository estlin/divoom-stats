import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let cpu = CPUSampler()
    private let mem = MemorySampler()
    private let disk = DiskSampler()
    private var macmon = MacmonSampler(intervalMs: Settings.shared.refreshSeconds * 1000)
    private let renderer = FrameRenderer()
    private let connection = MinitooConnection()

    private var statusItem: NSStatusItem!
    private var timer: DispatchSourceTimer?
    private var running = true
    private var settingsWindow: SettingsWindowController?

    private var lastError: String? = nil
    private var lastSentAt: Date? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📊"
        rebuildMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: Settings.changedNotification,
            object: nil
        )

        macmon.start()
        _ = cpu.sample()
        startTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // NOTE: previously sent Channel/SetClockSelectId here to hand the
        // display back to the device's built-in clock face. That puts the
        // Minitoo into "show stored clock face" mode, and the firmware then
        // *ignores incoming image frames* (cmd 0x8b) until the device is
        // power-cycled — making the next app launch appear broken. The
        // lesser evil is to leave the device on the last stats frame on quit.
        macmon.stop()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let status: String
        if connection.isConnected {
            status = "Connected: \(connection.deviceDescription)"
        } else {
            status = "Disconnected"
        }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
        if let e = lastError {
            menu.addItem(withTitle: "Error: \(e)", action: nil, keyEquivalent: "")
        }
        if !macmon.isAvailable {
            menu.addItem(withTitle: "macmon not found — temps disabled", action: nil, keyEquivalent: "")
        }
        if let last = lastSentAt {
            let secondsAgo = Int(Date().timeIntervalSince(last))
            menu.addItem(withTitle: "Last frame: \(secondsAgo)s ago", action: nil, keyEquivalent: "")
        }
        menu.addItem(NSMenuItem.separator())

        let toggle = NSMenuItem(
            title: running ? "Pause" : "Resume",
            action: #selector(togglePause),
            keyEquivalent: "p"
        )
        toggle.target = self
        menu.addItem(toggle)

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func togglePause() {
        running.toggle()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.show()
    }

    @objc private func settingsChanged() {
        let interval = TimeInterval(Settings.shared.refreshSeconds)

        // Restart the display timer at the new cadence.
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t

        // Restart macmon so its sample rate matches our display rate.
        macmon.stop()
        macmon = MacmonSampler(intervalMs: Settings.shared.refreshSeconds * 1000)
        macmon.start()
    }

    private func startTimer() {
        let interval = TimeInterval(Settings.shared.refreshSeconds)
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        guard running else { return }

        var stats = Stats()
        stats.cpuPercent = cpu.sample()
        let (rp, ru, rt) = mem.sample()
        stats.ramPercent = rp; stats.ramUsedGB = ru; stats.ramTotalGB = rt
        let (dp, du, dt) = disk.sample()
        stats.diskPercent = dp; stats.diskUsedGB = du; stats.diskTotalGB = dt

        if let m = macmon.current() {
            stats.cpuTempC = m.cpuTempC
            stats.gpuTempC = m.gpuTempC
            stats.gpuPercent = m.gpuPercent ?? 0
        }

        let pixels = renderer.render(stats)
        do {
            let packets = try MinitooProtocol.encodeImage(rgb888: pixels)
            try connection.send(packets)
            lastSentAt = Date()
            lastError = nil
        } catch {
            lastError = "\(error)"
            fputs("send failed: \(error)\n", stderr)
        }
        DispatchQueue.main.async { [weak self] in self?.rebuildMenu() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
