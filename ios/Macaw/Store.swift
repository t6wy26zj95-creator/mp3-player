import Foundation

/// The app's saved settings, under the same names (and in the same text format) as the web player's localStorage, so
/// what comes over from the old app and what syncs with your music server (/api/state) can be used as it is.
@MainActor
final class Store {
    static let shared = Store()
    private var values: [String: String] = [:]
    private let file: URL
    private var saveWork: Task<Void, Never>?

    private init() {
        file = Library.shared.supportFolder.appendingPathComponent("settings.json")
        if let d = try? Data(contentsOf: file), let v = try? JSONDecoder().decode([String: String].self, from: d) { values = v }
    }

    subscript(_ key: String) -> String? {
        get { values[key] }
        set {
            if values[key] == newValue { return }
            values[key] = newValue
            scheduleSave()
            Sync.shared.changed(key)
        }
    }

    /// Changes a key without telling the server (used when the change came from the server).
    func setQuietly(_ key: String, _ value: String?) { values[key] = value; scheduleSave() }

    var isEmpty: Bool { values.isEmpty }

    func json<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let s = values[key], let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    func setJSON<T: Encodable>(_ key: String, _ value: T) {
        guard let d = try? JSONEncoder().encode(value), let s = String(data: d, encoding: .utf8) else { return }
        self[key] = s
    }

    private func scheduleSave() {
        saveWork?.cancel()
        saveWork = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
    func saveNow() {
        saveWork = nil
        if let d = try? JSONEncoder().encode(values) { try? d.write(to: file, options: .atomic) }
    }
}
