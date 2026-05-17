import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var refreshButton: NSPopUpButton!
    private var unitButton: NSPopUpButton!

    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Settings"
        win.isReleasedWhenClosed = false
        win.center()
        self.init(window: win)
        win.delegate = self
        buildUI()
        loadValues()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let refreshLabel = NSTextField(labelWithString: "Refresh:")
        refreshLabel.frame = NSRect(x: 24, y: 104, width: 96, height: 20)
        refreshLabel.alignment = .right
        contentView.addSubview(refreshLabel)

        refreshButton = NSPopUpButton(frame: NSRect(x: 128, y: 100, width: 200, height: 26))
        refreshButton.addItems(withTitles: Settings.refreshOptions.map { secs in
            secs == 1 ? "1 second" : "\(secs) seconds"
        })
        refreshButton.target = self
        refreshButton.action = #selector(refreshChanged)
        contentView.addSubview(refreshButton)

        let unitLabel = NSTextField(labelWithString: "Temperature:")
        unitLabel.frame = NSRect(x: 24, y: 64, width: 96, height: 20)
        unitLabel.alignment = .right
        contentView.addSubview(unitLabel)

        unitButton = NSPopUpButton(frame: NSRect(x: 128, y: 60, width: 200, height: 26))
        unitButton.addItems(withTitles: ["Celsius (°C)", "Fahrenheit (°F)"])
        unitButton.target = self
        unitButton.action = #selector(unitChanged)
        contentView.addSubview(unitButton)

        let hint = NSTextField(labelWithString: "Changes apply immediately.")
        hint.frame = NSRect(x: 24, y: 18, width: 320, height: 18)
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 11)
        contentView.addSubview(hint)
    }

    private func loadValues() {
        let idx = Settings.refreshOptions.firstIndex(of: Settings.shared.refreshSeconds) ?? 1
        refreshButton.selectItem(at: idx)
        unitButton.selectItem(at: Settings.shared.tempUnit == .celsius ? 0 : 1)
    }

    @objc private func refreshChanged() {
        Settings.shared.refreshSeconds = Settings.refreshOptions[refreshButton.indexOfSelectedItem]
    }

    @objc private func unitChanged() {
        Settings.shared.tempUnit = unitButton.indexOfSelectedItem == 0 ? .celsius : .fahrenheit
    }

    /// Menu-bar (LSUIElement) apps don't normally show as foreground — but a
    /// preferences window should be modal-feeling. Activate the app so the
    /// window can take focus and accept input.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
