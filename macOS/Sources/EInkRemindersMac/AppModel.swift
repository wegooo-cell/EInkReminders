import EventKit
import Foundation

enum AutomaticSyncInterval: Int, CaseIterable, Identifiable {
    case thirtySeconds = 30
    case oneMinute = 60
    case tenMinutes = 600
    case thirtyMinutes = 1800
    case oneHour = 3600

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .thirtySeconds: return "30 秒"
        case .oneMinute: return "1 分钟"
        case .tenMinutes: return "10 分钟"
        case .thirtyMinutes: return "30 分钟"
        case .oneHour: return "1 小时"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var deviceURL: String {
        didSet {
            defaults.set(deviceURL, forKey: Keys.deviceURL)

            // 地址改了就重新记录设备：下一次同步以新地址上的 NOTE4 为准。
            defaults.removeObject(forKey: Keys.deviceId)
        }
    }
    @Published var selectedCalendarId: String? {
        didSet { defaults.set(selectedCalendarId, forKey: Keys.calendarId) }
    }
    @Published private(set) var calendars: [(id: String, title: String)] = []
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var activeView: DeviceReminderView = .today
    @Published private(set) var activeViewTotalCount = 0
    @Published private(set) var emptyState: ReminderEmptyState = .noItems
    @Published private(set) var statusText = "尚未同步"
    @Published private(set) var isSyncing = false

    /// 没能写回 Apple 提醒事项、已随确认从设备队列移除的操作，持久化保存直到用户清除。
    @Published private(set) var deadLetters: [DeadLetter] = []

    @Published private(set) var displayWidth = ZectrixDisplayRenderer.width
    @Published private(set) var displayHeight = ZectrixDisplayRenderer.height
    @Published var automaticSync: Bool {
        didSet {
            defaults.set(automaticSync, forKey: Keys.automaticSync)
            configureAutomaticSyncTimer()
        }
    }
    @Published var automaticSyncInterval: AutomaticSyncInterval {
        didSet {
            defaults.set(automaticSyncInterval.rawValue, forKey: Keys.automaticSyncInterval)
            configureAutomaticSyncTimer()
        }
    }

    private let defaults: UserDefaults
    private let reminderStore: ReminderStore
    private var timer: Timer?
    private var deviceRequestTimer: Timer?
    private var changeObserver: NSObjectProtocol?

    /// 系统日期变化的通知观察者，跨过午夜后触发同步。
    private var dayChangeObserver: NSObjectProtocol?

    private var reminderChangeSyncTask: Task<Void, Never>?
    private var reminderChangeSyncPending = false
    private var lastRenderedItems: [ReminderItem]?
    private var lastRenderProfile: String?
    private var lastRenderedEmptyState: ReminderEmptyState?

    /// 上一次渲染画面所在的日期；跨过午夜后页头日期和「今天 / 明天」标签都要重绘。
    private var lastRenderedDay: Date?

    private var cachedZectrixItems: [ReminderItem] = []
    private var cachedZectrixView: DeviceReminderView = .today
    private var cachedZectrixRevision: UInt64 = 0
    private var lastAlertSignatures: [String] = []
    private var isServingDisplayRequest = false

    /// 设备轮询的单飞标志，在第一次 await 之前置位。
    private var isPollingDevice = false

    /// 阻止 App Nap 节流计时器：设备按键出画面依赖每秒一次的轮询。
    private var pollingActivity: NSObjectProtocol?

    init(
        previewReminders: [ReminderItem] = [],
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        let identities = SyncIdentityStore()
        reminderStore = ReminderStore(identities: identities)
        deviceURL = defaults.string(forKey: Keys.deviceURL) ?? ""
        selectedCalendarId = defaults.string(forKey: Keys.calendarId)
        automaticSync = defaults.object(forKey: Keys.automaticSync) as? Bool ?? true
        automaticSyncInterval = AutomaticSyncInterval(
            rawValue: defaults.integer(forKey: Keys.automaticSyncInterval)
        ) ?? .thirtySeconds
        reminders = previewReminders
        activeViewTotalCount = previewReminders.count
        deadLetters = defaults.data(forKey: Keys.deadLetters)
            .flatMap { try? WireCoding.decoder().decode([DeadLetter].self, from: $0) } ?? []

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleReminderChangeSync()
            }
        }

        // 跨过午夜后立即同步一次，不等下一个同步周期，屏幕上的日期和相对时间标签随之更新。
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.automaticSync == true else { return }
                await self?.sync()
            }
        }

        // 窗口关闭或应用在后台时，App Nap 会节流计时器，设备按键要等很久才出画面；
        // 仍允许系统空闲睡眠。
        pollingActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "轮询 NOTE4 的按键与同步请求"
        )

        configureAutomaticSyncTimer()
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        if let dayChangeObserver { NotificationCenter.default.removeObserver(dayChangeObserver) }
        if let pollingActivity { ProcessInfo.processInfo.endActivity(pollingActivity) }
        reminderChangeSyncTask?.cancel()
        timer?.invalidate()
        deviceRequestTimer?.invalidate()
    }

    private func configureAutomaticSyncTimer() {
        timer?.invalidate()
        deviceRequestTimer?.invalidate()
        timer = nil
        deviceRequestTimer = nil
        if automaticSync {
            timer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(automaticSyncInterval.rawValue),
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor in
                    guard self?.automaticSync == true else { return }
                    await self?.sync()
                }
            }
        } else {
            reminderChangeSyncTask?.cancel()
            reminderChangeSyncTask = nil
            reminderChangeSyncPending = false
        }
        // A one-second device poll is still effectively immediate for button
        // interactions, while cutting idle Wi-Fi traffic to one quarter of the
        // previous rate so NOTE4 can spend time in modem sleep.
        deviceRequestTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollForDeviceSyncRequest() }
        }
    }

    private func scheduleReminderChangeSync() {
        guard automaticSync else { return }
        reminderChangeSyncPending = true
        reminderChangeSyncTask?.cancel()
        reminderChangeSyncTask = Task { [weak self] in
            // EventKit often emits several notifications for one edit. A very
            // short debounce lets the store settle without making the user
            // wait for the periodic fallback timer.
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            await self?.flushReminderChangeSync()
        }
    }

    private func flushReminderChangeSync() async {
        while automaticSync, reminderChangeSyncPending, !Task.isCancelled {
            // Never drop a change that arrives while another device request or
            // synchronization is active. Wait briefly, then run a fresh fetch.
            if isSyncing || isServingDisplayRequest {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    return
                }
                continue
            }
            reminderChangeSyncPending = false
            statusText = "检测到提醒事项变化，正在同步…"

            // 新的 EventKit 通知会取消本任务。同步放进独立任务，不随之取消，
            // 否则写回做到一半就会中断、操作得不到确认；新变化由下一轮循环处理。
            await Task { await sync(force: true) }.value
        }
    }

    private func pollForDeviceSyncRequest() async {
        guard !isPollingDevice,
              !isSyncing,
              !isServingDisplayRequest,
              let baseURL = normalizedURL else { return }

        // 计时器每秒新建一个任务：单飞标志必须在第一次 await 之前置位，上一轮没结束就跳过本轮，
        // 避免设备响应慢或离线时请求堆积、画面重叠乱序上传。
        isPollingDevice = true
        defer { isPollingDevice = false }

        do {
            let client = DeviceClient(baseURL: baseURL)
            let deviceStatus = try await client.status()

            // 等待状态期间可能已经开始同步：放弃本轮，避免在新快照之后上传按旧列表渲染的画面。
            guard !isSyncing else { return }

            if deviceStatus.displayRequested == true,
               deviceStatus.view == cachedZectrixView,
               deviceStatus.revision == cachedZectrixRevision,
               !cachedZectrixItems.isEmpty {
                isServingDisplayRequest = true
                defer { isServingDisplayRequest = false }
                let operations = try await client.operations(after: 0)
                try await sendZectrixInteractionFrames(
                    client: client,
                    items: cachedZectrixItems,
                    selectedOriginalIndex: deviceStatus.selectedIndex ?? 0,
                    queuedCompletionIDs: Set(Self.completedOnDeviceIDs(from: operations))
                )
                return
            }

            // 设备上的完成、切换视图和「立即同步」都是用户的明确操作，不受「自动同步」开关限制；
            // 开关只控制定时同步和提醒事项变化触发的同步。
            if deviceStatus.syncRequested == true,
               deviceStatus.syncRequestAgeMs.map({ $0 >= 5_000 }) ?? true {
                await sync()
            }
        } catch {
            // The full scheduled/manual sync remains responsible for showing
            // connection errors; silent polling must not overwrite UI status.
        }
    }

    func prepare() async {
        do {
            guard try await reminderStore.requestAccess() else {
                statusText = "未获得提醒事项权限"
                return
            }
            calendars = reminderStore.calendars.map { ($0.calendarIdentifier, $0.title) }

            // 保存的列表可能已被删除：和未选择一样改选第一个列表，不能带着失效的标识去同步。
            if !calendars.contains(where: { $0.id == selectedCalendarId }) {
                selectedCalendarId = calendars.first?.id
            }

            await sync()
        } catch {
            statusText = error.localizedDescription
        }
    }

    func sync(force: Bool = false) async {
        guard !isSyncing, !isServingDisplayRequest else { return }
        guard let baseURL = normalizedURL else {
            statusText = "设备地址无效"
            return
        }

        // 所选列表不可用时本轮同步无法完成、设备操作不会被确认：先停下，
        // 否则设备持续请求同步时，同一批操作会被反复写回 Apple 提醒事项。
        let hasSelectedList = reminderStore.calendars.contains {
            $0.calendarIdentifier == selectedCalendarId
        }
        guard hasSelectedList else {
            statusText = "同步失败：\(ReminderStore.StoreError.listUnavailable.localizedDescription)"
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let client = DeviceClient(baseURL: baseURL)
            let deviceStatus = try await client.status()

            // 等待状态期间设备地址可能被修改：读到的是旧地址上的设备，放弃本轮，也不能据此记录配对。
            guard normalizedURL == baseURL else { return }

            if !force,
               deviceStatus.syncRequested == true,
               let age = deviceStatus.syncRequestAgeMs,
               age < 5_000 {
                return
            }
            displayWidth = deviceStatus.width
            displayHeight = deviceStatus.height
            guard deviceStatus.width == ZectrixDisplayRenderer.width,
                  deviceStatus.height == ZectrixDisplayRenderer.height else {
                statusText = "同步失败：当前版本仅支持 ZECTRIX NOTE4 黑白版（400 × 300）"
                return
            }

            // 路由器可能把这个地址重新分配给另一台 NOTE4：只和第一次连上的设备同步，
            // 设备地址被修改后才重新记录。
            guard matchesPairedDevice(deviceStatus.deviceId) else {
                statusText = "同步失败：该地址上的 NOTE4 不是之前同步的设备，请确认设备地址"
                return
            }

            activeView = deviceStatus.view ?? .today
            let renderProfile = "zectrix-note4-\(deviceStatus.firmwareVersion ?? "unknown")-\(activeView.rawValue)"
            // The device's durable queue is the source of truth. Always read
            // every unacknowledged operation: firmware reinstall/reset can
            // restart its sequence at 1 while the device MAC stays unchanged.
            // Completion writes are idempotent and successful operations are
            // removed only by the ACK below.
            let operations = try await client.operations(after: 0)
            let sortedOperations = operations.sorted(by: { $0.sequence < $1.sequence })

            // 单条写回失败不中断同步，下方的确认覆盖本轮读到的全部操作。
            // 写回失败的操作先暂存，确认成功、它们从设备队列移除后才记入死信。
            let failedOperations = applyDeviceOperations(sortedOperations)

            let viewSnapshot = try await reminderStore.fetchView(
                activeView,
                calendarIdentifier: selectedCalendarId,
                includeAlertCandidates: true
            )
            activeViewTotalCount = viewSnapshot.totalCount
            emptyState = viewSnapshot.emptyState
            reminders = viewSnapshot.items

            // 页头日期、「今天 / 明天」标签和时段分组都在渲染时写死，跨天后即使事项不变也要重绘。
            let renderDay = Calendar.current.startOfDay(for: Date())
            let needsRefresh = lastRenderedItems != reminders ||
                lastRenderProfile != renderProfile ||
                lastRenderedEmptyState != emptyState ||
                lastRenderedDay != renderDay ||
                Self.requiresFrameRebuild(deviceRevision: deviceStatus.revision)
            let revision = UInt64(Date().timeIntervalSince1970 * 1_000)
            let now = Date()
            let alertItems = Self.pendingAlerts(from: viewSnapshot.alertCandidates, now: now)
            let alertSignatures = alertItems.map { "\($0.syncId)|\(Int64(($0.dueAt?.timeIntervalSince1970 ?? 0) * 1_000))|\($0.title)" }
            let alertsChanged = alertSignatures != lastAlertSignatures
            let shouldSendSnapshot = needsRefresh || alertsChanged || deviceStatus.syncRequested == true || !operations.isEmpty
            if shouldSendSnapshot {
                let alerts: [DeviceAlert]? = try alertItems.map { item in
                    DeviceAlert(
                        syncId: item.syncId, appleId: item.appleId,
                        dueAtEpochMs: Int64(item.dueAt!.timeIntervalSince1970 * 1_000),
                        bitmap: try ZectrixDisplayRenderer.renderAlertPatch(title: item.title).base64EncodedString()
                    )
                }
                try await client.send(snapshot: DeviceSnapshot(
                    revision: revision,
                    reminders: reminders,
                    viewCounts: nil,
                    currentViewCount: viewSnapshot.items.count,
                    replaceDisplay: needsRefresh,
                    sentAtEpochMs: Int64(Date().timeIntervalSince1970 * 1_000),
                    alerts: alerts
                ))
                cachedZectrixItems = reminders
                cachedZectrixView = activeView
                cachedZectrixRevision = revision
                lastAlertSignatures = alertSignatures
            }
            if needsRefresh {
                let selectableCount = activeView == .completed
                    ? reminders.count
                    : reminders.lazy.filter { !$0.completed }.count
                try await client.send(
                    display: try ZectrixDisplayRenderer.render(
                        reminders,
                        selectedIndex: nil,
                        view: activeView,
                        emptyState: emptyState
                    ),
                    index: 0,
                    state: .idle
                )
                if selectableCount > 0 {
                    try await sendZectrixInteractionFrames(
                        client: client,
                        items: reminders,
                        selectedOriginalIndex: 0,
                        queuedCompletionIDs: []
                    )
                }
                lastRenderedItems = reminders
                lastRenderProfile = renderProfile
                lastRenderedEmptyState = emptyState
                lastRenderedDay = renderDay
            }

            // 每条操作都已写回、确认提醒不存在或暂存为死信，快照和所需画面也都发送成功后，才确认操作。
            // 中途失败时设备会重放全部操作，已经完成的提醒不会被重复保存。
            if let last = operations.map(\.sequence).max() {
                try await client.acknowledge(through: last)
                recordDeadLetters(failedOperations)
            }
            if deviceStatus.syncRequested == true {
                try await client.acknowledgeSyncRequest()
            }
            statusText = "已同步“\(activeView.title)”视图 \(viewSnapshot.totalCount) 项\(needsRefresh ? "并刷新屏幕" : "") · \(Self.clock.string(from: Date()))"
        } catch {
            statusText = "同步失败：\(error.localizedDescription)"
        }
    }

    private func sendZectrixInteractionFrames(
        client: DeviceClient,
        items: [ReminderItem],
        selectedOriginalIndex: Int,
        queuedCompletionIDs: Set<String>
    ) async throws {
        let currentItems = Self.itemsMarkingCompleted(items, syncIds: queuedCompletionIDs)
        let selectedIndex = Self.renderSelectionIndex(
            originalIndex: selectedOriginalIndex,
            items: currentItems,
            view: activeView
        )
        try await client.send(
            display: try ZectrixDisplayRenderer.render(
                currentItems,
                selectedIndex: selectedIndex,
                view: activeView
            ),
            index: selectedOriginalIndex,
            state: .normal
        )

        guard activeView != .completed,
              currentItems.indices.contains(selectedOriginalIndex),
              !currentItems[selectedOriginalIndex].completed else { return }
        var predictedIDs = queuedCompletionIDs
        predictedIDs.insert(currentItems[selectedOriginalIndex].syncId)
        let predictedItems = Self.itemsMarkingCompleted(items, syncIds: predictedIDs)
        let nextOriginalIndex = Self.nextAvailableOriginalIndex(
            after: selectedOriginalIndex,
            items: predictedItems
        ) ?? selectedOriginalIndex
        let nextSelectedIndex = Self.renderSelectionIndex(
            originalIndex: nextOriginalIndex,
            items: predictedItems,
            view: activeView
        )
        try await client.send(
            display: try ZectrixDisplayRenderer.render(
                predictedItems,
                selectedIndex: nextSelectedIndex,
                view: activeView
            ),
            index: selectedOriginalIndex,
            state: .confirmation
        )
    }

    /// 判断设备是否为之前同步的那一台：第一次连上时记住设备 ID，之后只接受同一台设备。
    private func matchesPairedDevice(_ deviceId: String) -> Bool {
        guard let pairedDeviceId = defaults.string(forKey: Keys.deviceId) else {
            defaults.set(deviceId, forKey: Keys.deviceId)
            return true
        }

        return pairedDeviceId == deviceId
    }

    /// 把设备操作逐条写回 Apple 提醒事项，返回写回失败、需要记入死信的操作。
    private func applyDeviceOperations(_ operations: [DeviceOperation]) -> [DeadLetter] {
        var failed: [DeadLetter] = []

        for operation in operations {
            do {
                try reminderStore.apply(operation)
            } catch ReminderStore.StoreError.reminderNotFound {
                // 提醒已在其他设备上删除或标识已失效，没有可写回的对象，视为已处理。
                continue
            } catch {
                // 列表只读等错误重试也不会成功：记入死信并在界面提示。
                failed.append(DeadLetter(
                    operation: operation,
                    message: error.localizedDescription
                ))
            }
        }

        return failed
    }

    /// 记录已随确认从设备队列移除、但没能写回的操作，并持久化。
    private func recordDeadLetters(_ failed: [DeadLetter]) {
        guard !failed.isEmpty else { return }

        deadLetters.append(contentsOf: failed)
        defaults.set(try? WireCoding.encoder().encode(deadLetters), forKey: Keys.deadLetters)
    }

    /// 用户看过提示后清除全部死信。
    func clearDeadLetters() {
        deadLetters = []
        defaults.removeObject(forKey: Keys.deadLetters)
    }

    private var normalizedURL: URL? {
        var value = deviceURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // 未填写设备地址时视为无效，不访问任何设备。
        guard !value.isEmpty else { return nil }

        if !value.contains("://") { value = "http://" + value }
        return URL(string: value)
    }

    private static let clock: DateFormatter = {
        let value = DateFormatter()
        value.dateFormat = "HH:mm:ss"
        return value
    }()

    static func completedOnDeviceIDs(from operations: [DeviceOperation]) -> [String] {
        operations.compactMap { operation in
            operation.type == .setCompleted && operation.completed != false ? operation.syncId : nil
        }
    }

    static func pendingAlerts(from items: [ReminderItem], now: Date) -> [ReminderItem] {
        items.filter { item in
            !item.completed && item.hasDueTime &&
                (item.dueAt.map { $0 >= now.addingTimeInterval(-30) } ?? false)
        }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .prefix(32).map { $0 }
    }

    static func requiresFrameRebuild(deviceRevision: UInt64) -> Bool {
        // The NOTE4 marks its revision as zero after a local cache clear or
        // when its idle frame is missing. Re-upload the image even if EventKit
        // returns exactly the same reminders as last time.
        deviceRevision == 0
    }

    static func itemsMarkingCompleted(
        _ reminders: [ReminderItem],
        syncIds: Set<String>
    ) -> [ReminderItem] {
        reminders.map { item in
            guard syncIds.contains(item.syncId) else { return item }
            var completed = item
            completed.completed = true
            return completed
        }
    }

    static func renderSelectionIndex(
        originalIndex: Int,
        items: [ReminderItem],
        view: DeviceReminderView
    ) -> Int? {
        guard items.indices.contains(originalIndex) else { return nil }
        if view == .completed { return originalIndex }
        let selectedID = items[originalIndex].syncId
        return items.filter { !$0.completed }.firstIndex { $0.syncId == selectedID }
    }

    static func nextAvailableOriginalIndex(
        after originalIndex: Int,
        items: [ReminderItem]
    ) -> Int? {
        guard !items.isEmpty else { return nil }
        for offset in 1...items.count {
            let candidate = (originalIndex + offset) % items.count
            if !items[candidate].completed { return candidate }
        }
        return nil
    }

    private enum Keys {
        static let deviceURL = "deviceURL"
        static let calendarId = "calendarId"
        static let automaticSync = "automaticSync"
        static let automaticSyncInterval = "automaticSyncInterval"
        static let deviceId = "deviceId"
        static let deadLetters = "deadLetters"
    }
}
