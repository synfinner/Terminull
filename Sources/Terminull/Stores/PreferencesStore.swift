import Foundation

final class PreferencesStore: ObservableObject {
    @Published var preferences: AppPreferences {
        didSet {
            save()
        }
    }

    private let defaultsKey = "Terminull.AppPreferences"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = AppPreferences()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
