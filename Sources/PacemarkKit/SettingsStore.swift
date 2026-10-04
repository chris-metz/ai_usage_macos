import Foundation

/// Keeps the settings in `UserDefaults` (§6.5): the standard suite in the
/// app, a throwaway suite in tests.
public struct SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The stored settings. A missing or invalid value reads as its default,
    /// silently.
    public func load() -> Settings {
        let fallback = Settings()
        var settings = fallback
        if let minutes = value(Key.refreshIntervalMinutes, as: Int.self),
           Settings.refreshIntervalChoices.contains(minutes) {
            settings.refreshIntervalMinutes = minutes
        }
        settings.showPercentage = value(Key.showPercentage, as: Bool.self) ?? fallback.showPercentage
        settings.hiddenLimits = value(Key.hiddenLimits, as: [String].self) ?? fallback.hiddenLimits
        settings.menuBarLimitID = value(Key.menuBarLimitID, as: String.self)
        settings.menuBarLimitTitle = value(Key.menuBarLimitTitle, as: String.self)
        return settings
    }

    /// Writes every setting.
    public func save(_ settings: Settings) {
        defaults.set(settings.refreshIntervalMinutes, forKey: Key.refreshIntervalMinutes)
        defaults.set(settings.showPercentage, forKey: Key.showPercentage)
        defaults.set(settings.hiddenLimits, forKey: Key.hiddenLimits)
        defaults.set(settings.menuBarLimitID, forKey: Key.menuBarLimitID)
        defaults.set(settings.menuBarLimitTitle, forKey: Key.menuBarLimitTitle)
    }

    /// The stored value if it has the type, e.g. never a string as a number.
    private func value<Value>(_ key: String, as type: Value.Type) -> Value? {
        defaults.object(forKey: key) as? Value
    }

    private enum Key {
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
        static let showPercentage = "showPercentage"
        static let hiddenLimits = "hiddenLimits"
        static let menuBarLimitID = "menuBarLimitID"
        static let menuBarLimitTitle = "menuBarLimitTitle"
    }
}
