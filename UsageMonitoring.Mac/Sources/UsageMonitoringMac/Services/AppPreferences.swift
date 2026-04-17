import Foundation

final class AppPreferences {
    private enum Key {
        static let codexExecutablePath = "codexExecutablePath"
        static let windowPlacement = "windowPlacement"
        static let launchAtLogin = "launchAtLogin"
        static let clickThroughEnabled = "clickThroughEnabled"
    }

    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var codexExecutablePath: String? {
        get { defaults.string(forKey: Key.codexExecutablePath) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Key.codexExecutablePath)
            } else {
                defaults.removeObject(forKey: Key.codexExecutablePath)
            }
        }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    var clickThroughEnabled: Bool {
        get { defaults.bool(forKey: Key.clickThroughEnabled) }
        set { defaults.set(newValue, forKey: Key.clickThroughEnabled) }
    }

    func loadWindowPlacement() -> WindowPlacement? {
        guard let data = defaults.data(forKey: Key.windowPlacement) else {
            return nil
        }

        return try? decoder.decode(WindowPlacement.self, from: data)
    }

    func saveWindowPlacement(_ placement: WindowPlacement) {
        guard let data = try? encoder.encode(placement) else {
            return
        }

        defaults.set(data, forKey: Key.windowPlacement)
    }
}
