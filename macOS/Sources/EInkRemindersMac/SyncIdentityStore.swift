import Foundation

final class SyncIdentityStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "appleToSyncIdentity.v1"
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func syncId(for appleId: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        var mapping = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        if let existing = mapping[appleId] { return existing }
        let created = UUID().uuidString.lowercased()
        mapping[appleId] = created
        defaults.set(mapping, forKey: key)
        return created
    }

    func bind(syncId: String, to appleId: String) {
        lock.lock()
        defer { lock.unlock() }
        var mapping = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        mapping[appleId] = syncId
        defaults.set(mapping, forKey: key)
    }

    func appleId(for syncId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let mapping = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return mapping.first(where: { $0.value == syncId })?.key
    }
}

