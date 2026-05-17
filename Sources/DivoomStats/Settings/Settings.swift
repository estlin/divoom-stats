import Foundation

/// User-facing preferences, persisted in UserDefaults. Observers can listen for
/// `Settings.changedNotification` to re-apply on change.
final class Settings {
    static let shared = Settings()
    static let changedNotification = Notification.Name("DivoomStats.SettingsChanged")

    enum TempUnit: String { case celsius = "C", fahrenheit = "F" }

    static let refreshOptions: [Int] = [1, 2, 5, 10, 30]
    static let defaultRefreshSeconds = 2

    private let defaults = UserDefaults.standard
    private let kRefresh = "refreshSeconds"
    private let kUnit = "tempUnit"

    var refreshSeconds: Int {
        get {
            let v = defaults.integer(forKey: kRefresh)
            return Self.refreshOptions.contains(v) ? v : Self.defaultRefreshSeconds
        }
        set {
            defaults.set(newValue, forKey: kRefresh)
            post()
        }
    }

    var tempUnit: TempUnit {
        get { TempUnit(rawValue: defaults.string(forKey: kUnit) ?? "") ?? .celsius }
        set { defaults.set(newValue.rawValue, forKey: kUnit); post() }
    }

    /// Convert a Celsius temperature to the user's preferred unit and format it
    /// for display (zero decimal places, with degree symbol + unit suffix).
    func formatTemp(_ celsius: Double) -> String {
        switch tempUnit {
        case .celsius:
            return String(format: "%.0f°C", celsius)
        case .fahrenheit:
            return String(format: "%.0f°F", celsius * 9.0 / 5.0 + 32.0)
        }
    }

    private func post() {
        NotificationCenter.default.post(name: Settings.changedNotification, object: nil)
    }
}
