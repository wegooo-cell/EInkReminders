import Foundation

final class SyncIdentityStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "appleToSyncIdentity.v1"
    private let lock = NSLock()

    /// UserDefaults 中 appleId → syncId 映射的内存副本：查找只读内存，映射变化时才写回 UserDefaults。
    private var syncIdsByAppleId: [String: String]

    /// syncId → appleId 的反向索引，按 syncId 直接查找。
    private var appleIdsBySyncId: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        syncIdsByAppleId = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        appleIdsBySyncId = Dictionary(
            syncIdsByAppleId.map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func syncId(for appleId: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        if let existing = syncIdsByAppleId[appleId] { return existing }

        let created = UUID().uuidString.lowercased()
        syncIdsByAppleId[appleId] = created
        appleIdsBySyncId[created] = appleId

        defaults.set(syncIdsByAppleId, forKey: key)
        return created
    }

    func bind(syncId: String, to appleId: String) {
        lock.lock()
        defer { lock.unlock() }

        // 映射没有变化时不写 UserDefaults：每次写回设备操作都会调用这里。
        guard syncIdsByAppleId[appleId] != syncId else { return }

        // 这条提醒改绑到新的 syncId，旧 syncId 的反向索引随之失效。
        if let previous = syncIdsByAppleId[appleId], appleIdsBySyncId[previous] == appleId {
            appleIdsBySyncId.removeValue(forKey: previous)
        }

        syncIdsByAppleId[appleId] = syncId
        appleIdsBySyncId[syncId] = appleId

        defaults.set(syncIdsByAppleId, forKey: key)
    }

    func appleId(for syncId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        return appleIdsBySyncId[syncId]
    }

    /// 删除已确认不存在的提醒的映射。
    func remove(appleId: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let syncId = syncIdsByAppleId.removeValue(forKey: appleId) else { return }

        if appleIdsBySyncId[syncId] == appleId {
            appleIdsBySyncId.removeValue(forKey: syncId)
        }

        defaults.set(syncIdsByAppleId, forKey: key)
    }
}

