import Foundation

/// A saved khutba: the captured Arabic sentences and their translations from one
/// live-translation session. This is Siraat's distinctive feature — no other app lets
/// you keep and revisit the sermons you attended.
struct KhutbaSession: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    var title: String
    let segments: [LiveSegment]

    init(id: UUID = UUID(), date: Date, title: String, segments: [LiveSegment]) {
        self.id = id
        self.date = date
        self.title = title
        self.segments = segments
    }
}

/// Persists saved khutbas. Backed by UserDefaults (JSON); injectable for testing.
struct KhutbaLibraryStore {
    private let userDefaults: UserDefaults
    private let key = "khutba.library.v1"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func all() -> [KhutbaSession] {
        guard let data = userDefaults.data(forKey: key),
              let sessions = try? JSONDecoder().decode([KhutbaSession].self, from: data) else {
            return []
        }
        return sessions
    }

    @discardableResult
    func save(_ session: KhutbaSession) -> [KhutbaSession] {
        var sessions = all()
        sessions.removeAll { $0.id == session.id }
        sessions.insert(session, at: 0) // newest first
        persist(sessions)
        return sessions
    }

    @discardableResult
    func delete(id: UUID) -> [KhutbaSession] {
        let sessions = all().filter { $0.id != id }
        persist(sessions)
        return sessions
    }

    private func persist(_ sessions: [KhutbaSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        userDefaults.set(data, forKey: key)
    }
}
