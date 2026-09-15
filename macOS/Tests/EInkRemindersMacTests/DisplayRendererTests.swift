import AppKit
import EventKit
import SwiftUI
import XCTest
@testable import EInkRemindersMac

final class DisplayRendererTests: XCTestCase {
    func testAlertPatchFitsTheCenteredNote4Card() throws {
        let patch = try ZectrixDisplayRenderer.renderAlertPatch(title: "提交项目方案")
        XCTAssertEqual(patch.count, 280 * 78 / 8)
        XCTAssertTrue(patch.contains { $0 != 0xFF })
        XCTAssertEqual(patch, try ZectrixDisplayRenderer.renderAlertPatch(title: "提交项目方案"))
    }

    @MainActor
    func testOnlyUpcomingTimedTasksBecomeAlerts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func item(_ id: String, offset: TimeInterval?, timed: Bool = true, completed: Bool = false) -> ReminderItem {
            ReminderItem(syncId: id, title: id, dueAt: offset.map { now.addingTimeInterval($0) },
                         hasDueTime: timed, completed: completed, priority: 0, updatedAt: now)
        }
        let alerts = AppModel.pendingAlerts(from: [
            item("future", offset: 3600), item("near", offset: -20),
            item("old", offset: -60), item("date-only", offset: 7200, timed: false),
            item("done", offset: 60, completed: true), item("undated", offset: nil)
        ], now: now)
        XCTAssertEqual(alerts.map(\.syncId), ["near", "future"])
    }

    @MainActor
    func testNote4RebuildsAnUnchangedViewAfterDeviceCacheClear() {
        XCTAssertTrue(AppModel.requiresFrameRebuild(deviceRevision: 0, forZectrix: true))
        XCTAssertFalse(AppModel.requiresFrameRebuild(deviceRevision: 42, forZectrix: true))
        XCTAssertFalse(AppModel.requiresFrameRebuild(deviceRevision: 0, forZectrix: false))
    }

    func testEmptyStateUsesTheSameWordingForAllFourViews() throws {
        XCTAssertEqual(ReminderEmptyState.noItems.message, "目前没有事项")
        XCTAssertEqual(ReminderEmptyState.allCompleted.message, "都忙完了玩去吧")

        for view in DeviceReminderView.allCases {
            let noItems = ReminderEmptyState.resolve(
                view: view, visibleCount: 0,
                hasCompletedTodayItems: false
            )
            XCTAssertEqual(noItems, .noItems)
            XCTAssertEqual(
                try ZectrixDisplayRenderer.render([], view: view, emptyState: noItems).count,
                ZectrixDisplayRenderer.packedByteCount
            )
        }
    }

    func testOnlyFinishedTodayViewUsesCelebration() throws {
        XCTAssertEqual(
            ReminderEmptyState.resolve(
                view: .today, visibleCount: 0,
                hasCompletedTodayItems: true
            ), .allCompleted
        )
        for view in [DeviceReminderView.scheduled, .all, .completed] {
            XCTAssertEqual(
                ReminderEmptyState.resolve(
                    view: view, visibleCount: 0,
                    hasCompletedTodayItems: true
                ), .noItems
            )
        }
        XCTAssertEqual(
            ReminderEmptyState.resolve(
                view: .today, visibleCount: 1,
                hasCompletedTodayItems: true
            ), .noItems
        )

        let empty = try ZectrixDisplayRenderer.render(
            [], view: .today, emptyState: .noItems
        )
        let finished = try ZectrixDisplayRenderer.render(
            [], view: .today, emptyState: .allCompleted
        )
        XCTAssertNotEqual(empty, finished)
    }

    @MainActor
    func testEventKitChangeTriggersSyncWithoutWaitingForPeriodicTimer() async throws {
        let suiteName = "EInkRemindersEventSync-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "automaticSync")
        defaults.set(AutomaticSyncInterval.oneHour.rawValue, forKey: "automaticSyncInterval")

        let model = AppModel(defaults: defaults)
        model.deviceURL = "%"
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(model.statusText, "设备地址无效")
    }

    func testTomorrowMorningIsNotClassifiedAsTodayAtNight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 23))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 11))!
        let reminder = ReminderItem(
            syncId: "tomorrow", title: "明天上午事项", dueAt: tomorrow,
            hasDueTime: true, completed: false, priority: 0, updatedAt: now
        )
        XCTAssertFalse(ReminderStore.belongsToToday(reminder, now: now, calendar: calendar))
        XCTAssertEqual(DisplayRenderer.displayDueLabel(for: reminder, relativeTo: now), "明天 11:00")
        XCTAssertNil(DisplayRenderer.dayPeriod(for: reminder, relativeTo: now))
    }

    func testAllViewRendersTodayAndTomorrowRows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 12, hour: 23
        ))!
        func item(_ id: String, day: Int, hour: Int) -> ReminderItem {
            ReminderItem(
                syncId: id,
                title: "事项 \(id)",
                dueAt: calendar.date(from: DateComponents(
                    year: 2026, month: 9, day: day, hour: hour
                )),
                hasDueTime: true,
                completed: false,
                priority: 0,
                updatedAt: now
            )
        }
        let tonight = item("今晚", day: 12, hour: 23)
        let allItems = [
            tonight,
            item("明天一", day: 13, hour: 9),
            item("明天二", day: 13, hour: 11),
            item("明天三", day: 13, hour: 15)
        ]

        let oneRow = try ZectrixDisplayRenderer.render(
            [tonight], view: .all, generatedAt: now
        )
        let fourRows = try ZectrixDisplayRenderer.render(
            allItems, view: .all, generatedAt: now
        )
        let blackPixels: (Data) -> Int = { data in
            data.reduce(0) { count, byte in
                count + (8 - byte.nonzeroBitCount)
            }
        }

        // Three additional rendered rows add far more pixels than the single
        // footer digit that changes from 1 to 4. This catches the former bug,
        // where future timed rows were counted but never drawn.
        XCTAssertGreaterThan(blackPixels(fourRows) - blackPixels(oneRow), 500)
    }

    func testScheduledViewRendersTodayTomorrowAndLaterRows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 12, hour: 21
        ))!
        func item(_ id: String, day: Int, hour: Int) -> ReminderItem {
            ReminderItem(
                syncId: id,
                title: "计划 \(id)",
                dueAt: calendar.date(from: DateComponents(
                    year: 2026, month: 9, day: day, hour: hour
                )),
                hasDueTime: true,
                completed: false,
                priority: 0,
                updatedAt: now
            )
        }
        let today = item("今天", day: 12, hour: 22)
        let scheduled = [
            today,
            item("明天", day: 13, hour: 9),
            item("后天", day: 14, hour: 15)
        ]

        let oneRow = try ZectrixDisplayRenderer.render(
            [today], view: .scheduled, generatedAt: now
        )
        let threeRows = try ZectrixDisplayRenderer.render(
            scheduled, view: .scheduled, generatedAt: now
        )
        let blackPixels: (Data) -> Int = { data in
            data.reduce(0) { count, byte in
                count + (8 - byte.nonzeroBitCount)
            }
        }

        XCTAssertGreaterThan(blackPixels(threeRows) - blackPixels(oneRow), 300)
    }

    func testUndatedReminderStillBelongsToToday() {
        let now = Date()
        let reminder = ReminderItem(
            syncId: "undated", title: "无日期事项", completed: false,
            priority: 0, updatedAt: now
        )
        XCTAssertTrue(ReminderStore.belongsToToday(reminder, now: now, calendar: .current))
    }

    func testNote4SmartViewChangesTheRenderedHeader() throws {
        XCTAssertNotEqual(
            try ZectrixDisplayRenderer.render([], view: .today),
            try ZectrixDisplayRenderer.render([], view: .scheduled)
        )
    }

    func testDeviceCompletionCarriesStableAppleIdentifier() throws {
        let data = Data(#"{"sequence":7,"type":"setCompleted","syncId":"device-7","appleId":"EK-REMINDER-7","completed":true}"#.utf8)
        let operation = try WireCoding.decoder().decode(DeviceOperation.self, from: data)
        XCTAssertEqual(operation.appleId, "EK-REMINDER-7")
        XCTAssertEqual(operation.syncId, "device-7")
        XCTAssertEqual(operation.completed, true)
    }

    @MainActor
    func testNote4DropsConfirmedRowsOnTheNextRefresh() {
        let now = Date()
        let pending = ReminderItem(syncId: "pending", title: "待办", completed: false, priority: 0, updatedAt: now)
        let completed = ReminderItem(syncId: "done", title: "已完成", completed: true, priority: 0, updatedAt: now)
        XCTAssertEqual(
            AppModel.remindersForDisplay(incomplete: [pending], completedOnDevice: [completed], usesZectrixFrame: true),
            [pending]
        )
        XCTAssertEqual(
            AppModel.remindersForDisplay(incomplete: [pending], completedOnDevice: [completed], usesZectrixFrame: false),
            [pending, completed]
        )
    }

    func testPackedDisplayHasExpectedSize() throws {
        let data = try DisplayRenderer.render([])
        XCTAssertEqual(data.count, 38_880)
    }

    func testZectrixFrameHasNativeSizeAndWhitePolarity() throws {
        let data = try ZectrixDisplayRenderer.render([])
        XCTAssertEqual(data.count, 15_000)
        XCTAssertTrue(data.contains(0xFF), "Note4 uses one bits for white pixels")
        XCTAssertTrue(data.contains { $0 != 0xFF }, "The empty-state message must contain black pixels")
    }

    func testZectrixPreviewUsesPhysicalResolution() throws {
        let image = try ZectrixDisplayRenderer.previewImage([])
        XCTAssertEqual(image.width, 400)
        XCTAssertEqual(image.height, 300)
    }

    func testZectrixSelectedRowsProduceDistinctNativeFrames() throws {
        let now = Date()
        let reminders = [
            ReminderItem(syncId: "1", title: "第一项", completed: false, priority: 0, updatedAt: now),
            ReminderItem(syncId: "2", title: "第二项", completed: false, priority: 0, updatedAt: now)
        ]
        XCTAssertNotEqual(
            try ZectrixDisplayRenderer.render(reminders, selectedIndex: 0, generatedAt: now),
            try ZectrixDisplayRenderer.render(reminders, selectedIndex: 1, generatedAt: now)
        )
    }

    func testZectrixOmitsEmojiWithoutChangingTheRemainingTitle() throws {
        let now = Date()
        let plainTitle = ReminderItem(
            syncId: "emoji", title: "提醒喝咖啡", completed: false,
            priority: 0, updatedAt: now
        )
        let emojiTitle = ReminderItem(
            syncId: "emoji", title: "☕️ 提醒喝咖啡", completed: false,
            priority: 0, updatedAt: now
        )
        XCTAssertEqual(
            try ZectrixDisplayRenderer.render([plainTitle], generatedAt: now),
            try ZectrixDisplayRenderer.render([emojiTitle], generatedAt: now)
        )
    }

    func testZectrixEmojiRemovalHandlesMixedAndEmojiOnlyTitles() {
        XCTAssertEqual(ZectrixDisplayRenderer.titleWithoutEmoji("🎬 写视频脚本 ✂️"), "写视频脚本")
        XCTAssertEqual(ZectrixDisplayRenderer.titleWithoutEmoji("☕️"), "未命名事项")
    }

    func testExportOptimizedZectrixPreviewWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["EINK_ZECTRIX_PREVIEW_PATH"] else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let generatedAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 8))!
        func item(_ id: String, _ title: String, hour: Int?, minute: Int = 0) -> ReminderItem {
            ReminderItem(
                syncId: id,
                title: title,
                dueAt: hour.map {
                    calendar.date(from: DateComponents(
                        year: 2026, month: 9, day: 10, hour: $0, minute: minute
                    ))!
                },
                hasDueTime: hour != nil,
                completed: false,
                priority: 0,
                updatedAt: generatedAt
            )
        }
        let reminders = [
            item("script", "🎬 写视频脚本", hour: 10),
            item("edit", "✂️ 剪视频", hour: 10, minute: 30)
        ]
        let image = try ZectrixDisplayRenderer.previewImage(
            reminders,
            selectedIndex: nil,
            generatedAt: generatedAt
        )
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("无法导出 NOTE4 预览")
            return
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: url)
    }

    func testPackingUsesMostSignificantBitFirst() {
        var pixels = [UInt8](repeating: 255, count: DisplayRenderer.width * DisplayRenderer.height)
        pixels[0] = 0
        pixels[7] = 0
        let data = DisplayRenderer.packBlackPixels(pixels)
        XCTAssertEqual(data.first, 0b1000_0001)
    }

    func testSelectedRowProducesDistinctFrame() throws {
        let now = Date()
        let reminders = [
            ReminderItem(syncId: "1", appleId: nil, title: "第一项", notes: nil, dueAt: nil, completed: false, priority: 0, updatedAt: now),
            ReminderItem(syncId: "2", appleId: nil, title: "第二项", notes: nil, dueAt: nil, completed: false, priority: 0, updatedAt: now)
        ]
        XCTAssertNotEqual(
            try DisplayRenderer.render(reminders, selectedIndex: 0, generatedAt: now),
            try DisplayRenderer.render(reminders, selectedIndex: 1, generatedAt: now)
        )
    }

    func testCompletedRowUsesDistinctCheckedAndStruckStyle() throws {
        let now = Date()
        let pending = ReminderItem(
            syncId: "1", title: "回复设计评审", completed: false, priority: 0, updatedAt: now
        )
        var completed = pending
        completed.completed = true
        XCTAssertNotEqual(
            try DisplayRenderer.render([pending], generatedAt: now),
            try DisplayRenderer.render([completed], generatedAt: now)
        )
    }

    func testCompletedRowReservesTheLastVisibleSlot() {
        let now = Date()
        let pending = (0..<5).map {
            ReminderItem(
                syncId: String($0), title: "事项 \($0)", completed: false,
                priority: 0, updatedAt: now
            )
        }
        XCTAssertEqual(
            DisplayRenderer.visiblePendingItems(pending, selectedIndex: 0, capacity: 4).map(\.syncId),
            ["0", "1", "2", "3"]
        )
        XCTAssertEqual(
            DisplayRenderer.visiblePendingItems(pending, selectedIndex: 4, capacity: 4).map(\.syncId),
            ["1", "2", "3", "4"]
        )
    }

    @MainActor
    func testLocalCompletionStatePreservesSeveralCompletedItems() {
        let now = Date()
        let reminders = ["第一项", "第二项", "第三项"].enumerated().map {
            ReminderItem(
                syncId: String($0.offset), title: $0.element,
                completed: false, priority: 0, updatedAt: now
            )
        }
        let preview = AppModel.itemsMarkingCompleted(reminders, syncIds: ["0", "1"])
        XCTAssertEqual(preview.map(\.syncId), ["0", "1", "2"])
        XCTAssertEqual(preview.map(\.completed), [true, true, false])
        XCTAssertEqual(
            AppModel.renderSelectionIndex(originalIndex: 2, items: preview, view: .today),
            0
        )
    }

    @MainActor
    func testOnDemandCompletionPreviewSupportsTwentyItems() throws {
        let now = Date()
        let reminders = (0..<20).map {
            ReminderItem(
                syncId: String($0), title: "事项 \($0 + 1)", completed: false,
                priority: 0, updatedAt: now
            )
        }
        let items = AppModel.itemsMarkingCompleted(reminders, syncIds: ["0", "7", "18"])
        let selected = AppModel.renderSelectionIndex(originalIndex: 19, items: items, view: .all)
        XCTAssertEqual(selected, 16)
        XCTAssertEqual(AppModel.nextAvailableOriginalIndex(after: 19, items: items), 1)
        XCTAssertEqual(
            try ZectrixDisplayRenderer.render(items, selectedIndex: selected, view: .all).count,
            ZectrixDisplayRenderer.packedByteCount
        )
    }

    func testZectrixCanSelectBeyondTheFirstFiveItems() throws {
        let now = Date()
        let reminders = (0..<20).map {
            ReminderItem(
                syncId: String($0), title: "事项 \($0 + 1)", completed: false,
                priority: 0, updatedAt: now
            )
        }
        XCTAssertNotEqual(
            try ZectrixDisplayRenderer.render(reminders, selectedIndex: 4, view: .today),
            try ZectrixDisplayRenderer.render(reminders, selectedIndex: 19, view: .today)
        )
    }

    func testZectrixCompletedViewShowsSixItemsPerPage() throws {
        let now = Date()
        let completed = (0..<7).map {
            ReminderItem(
                syncId: String($0), title: "已完成事项 \($0 + 1)", completed: true,
                priority: 0, updatedAt: now
            )
        }
        XCTAssertEqual(
            DisplayRenderer.visiblePendingItems(completed, selectedIndex: 5, capacity: 6).count,
            6
        )
        XCTAssertNotEqual(
            try ZectrixDisplayRenderer.render(completed, selectedIndex: 5, view: .completed),
            try ZectrixDisplayRenderer.render(completed, selectedIndex: 6, view: .completed)
        )
    }

    @MainActor
    func testOnlyDeviceCompletionOperationsCreateTransientRows() {
        let completedOnDevice = DeviceOperation(
            sequence: 1, type: .setCompleted, syncId: "device", completed: true
        )
        let reopenedOnDevice = DeviceOperation(
            sequence: 2, type: .setCompleted, syncId: "reopened", completed: false
        )
        let createdOnDevice = DeviceOperation(
            sequence: 3, type: .create, syncId: "created", title: "新事项"
        )
        XCTAssertEqual(
            AppModel.completedOnDeviceIDs(
                from: [completedOnDevice, reopenedOnDevice, createdOnDevice]
            ),
            ["device"]
        )
        XCTAssertTrue(AppModel.completedOnDeviceIDs(from: []).isEmpty)
    }

    func testDueLabelsDefaultToTodayUnlessThereIsASpecificTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 8))!
        let atTen = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 10))!
        let noDate = ReminderItem(syncId: "1", appleId: nil, title: "无日期", notes: nil, dueAt: nil, completed: false, priority: 0, updatedAt: now)
        let dateOnly = ReminderItem(syncId: "2", appleId: nil, title: "只有日期", notes: nil, dueAt: now, completed: false, priority: 0, updatedAt: now)
        let timed = ReminderItem(syncId: "3", appleId: nil, title: "具体时间", notes: nil, dueAt: atTen, hasDueTime: true, completed: false, priority: 0, updatedAt: now)

        XCTAssertEqual(DisplayRenderer.displayDueLabel(for: noDate, relativeTo: now), "今天")
        XCTAssertEqual(DisplayRenderer.displayDueLabel(for: dateOnly, relativeTo: now), "今天")
        XCTAssertEqual(DisplayRenderer.displayDueLabel(for: timed, relativeTo: now), "10:00")
    }

    func testSpecificTimesMapToDayPeriods() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let day = DateComponents(year: 2026, month: 9, day: 10)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 8))!
        func item(_ hour: Int) -> ReminderItem {
            var components = day
            components.hour = hour
            return ReminderItem(
                syncId: String(hour), title: "事项", dueAt: calendar.date(from: components), hasDueTime: true,
                completed: false, priority: 0, updatedAt: Date()
            )
        }

        XCTAssertEqual(DisplayRenderer.dayPeriod(for: item(9), relativeTo: reference), .morning)
        XCTAssertEqual(DisplayRenderer.dayPeriod(for: item(14), relativeTo: reference), .afternoon)
        XCTAssertEqual(DisplayRenderer.dayPeriod(for: item(16), relativeTo: reference), .afternoon)
        XCTAssertEqual(DisplayRenderer.dayPeriod(for: item(17), relativeTo: reference), .evening)
        XCTAssertEqual(DisplayRenderer.dayPeriod(for: item(19), relativeTo: reference), .evening)
    }

    func testAutomaticSyncIntervalsMatchTheUserChoices() {
        XCTAssertEqual(
            AutomaticSyncInterval.allCases.map(\.title),
            ["30 秒", "1 分钟", "10 分钟", "30 分钟", "1 小时"]
        )
    }

    func testPreviewImageUsesThePhysicalDisplayResolution() throws {
        let image = try DisplayRenderer.previewImage([])
        XCTAssertEqual(image.width, 648)
        XCTAssertEqual(image.height, 480)
    }

    @MainActor
    func testExportMacSyncWindowPreviewWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["EINK_MAC_UI_PREVIEW_PATH"] else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let generatedAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 8))!
        func item(_ title: String, hour: Int?, minute: Int = 0) -> ReminderItem {
            ReminderItem(
                syncId: UUID().uuidString,
                title: title,
                dueAt: hour.map {
                    calendar.date(from: DateComponents(
                        year: 2026, month: 9, day: 10, hour: $0, minute: minute
                    ))!
                },
                hasDueTime: hour != nil,
                completed: false,
                priority: 0,
                updatedAt: generatedAt
            )
        }
        let previewSuiteName = "EInkRemindersPreview-\(UUID().uuidString)"
        let previewDefaults = UserDefaults(suiteName: previewSuiteName)!
        defer { previewDefaults.removePersistentDomain(forName: previewSuiteName) }
        let model = AppModel(previewReminders: [
            item("整理今日计划", hour: nil),
            item("回复设计评审", hour: 10),
            item("剪辑产品视频", hour: 14),
            item("准备咖啡", hour: 15),
            item("晚间散步", hour: 19, minute: 30)
        ], defaults: previewDefaults)
        model.deviceURL = "http://192.168.1.42"
        model.automaticSync = true
        model.automaticSyncInterval = .oneMinute

        let renderer = ImageRenderer(content: ContentView().environmentObject(model))
        renderer.scale = 2
        guard let tiff = renderer.nsImage?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("无法渲染 Mac 界面预览")
            return
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: url)
    }

    func testExportSelectedDesignPreviewWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["EINK_PREVIEW_PATH"] else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let generatedAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 8))!
        func item(_ title: String, hour: Int?, minute: Int = 0, priority: Int = 0) -> ReminderItem {
            ReminderItem(
                syncId: UUID().uuidString, appleId: nil, title: title, notes: nil,
                dueAt: hour.map { calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: $0, minute: minute))! },
                hasDueTime: hour != nil, completed: false, priority: priority, updatedAt: generatedAt
            )
        }
        let reminders = [
            item("整理今日计划", hour: nil, priority: 1),
            item("回复设计评审", hour: 10),
            item("剪辑产品视频", hour: 14),
            item("准备咖啡", hour: 15),
            item("晚间散步", hour: 19, minute: 30)
        ]
        let packed = try DisplayRenderer.render(reminders, generatedAt: generatedAt)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try DisplayRenderer.pbmPreview(packed).write(to: URL(fileURLWithPath: path))
    }

    @MainActor
    func testExportPhoneCompletionSimulationWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["EINK_COMPLETION_SIMULATION_PATH"] else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let generatedAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 8))!
        func item(_ id: String, _ title: String, hour: Int?, minute: Int = 0) -> ReminderItem {
            ReminderItem(
                syncId: id,
                title: title,
                dueAt: hour.map {
                    calendar.date(from: DateComponents(
                        year: 2026, month: 9, day: 10, hour: $0, minute: minute
                    ))!
                },
                hasDueTime: hour != nil,
                completed: false,
                priority: 0,
                updatedAt: generatedAt
            )
        }

        let completedID = "design-review"
        let before = [
            item("plan", "整理今日计划", hour: nil),
            item(completedID, "回复设计评审", hour: 10),
            item("video", "剪辑产品视频", hour: 14),
            item("walk", "晚间散步", hour: 19, minute: 30)
        ]
        let after = before.map { item -> ReminderItem in
            guard item.syncId == completedID else { return item }
            var completed = item
            completed.completed = true
            return completed
        }
        let beforeScreen = try DisplayRenderer.previewImage(before, selectedIndex: 0, generatedAt: generatedAt)
        let afterScreen = try DisplayRenderer.previewImage(after, selectedIndex: 0, generatedAt: generatedAt)

        let canvasSize = NSSize(width: 1440, height: 690)
        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()

        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let titleStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 31, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1)
        ]
        let subtitleStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.38, alpha: 1)
        ]
        ("在墨水屏双击完成待办后" as NSString).draw(at: NSPoint(x: 42, y: 638), withAttributes: titleStyle)
        ("本次同步紧跟现有项目显示完成状态；下一次同步刷新时再移除" as NSString)
            .draw(at: NSPoint(x: 42, y: 607), withAttributes: subtitleStyle)

        func drawPanel(
            x: CGFloat,
            label: String,
            detail: String,
            screen: CGImage,
            completionBadge: Bool
        ) {
            let panel = NSRect(x: x, y: 38, width: 676, height: 545)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: panel, xRadius: 22, yRadius: 22).fill()

            let labelStyle: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
            ]
            let detailStyle: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.48, alpha: 1)
            ]
            (label as NSString).draw(at: NSPoint(x: x + 18, y: 548), withAttributes: labelStyle)
            (detail as NSString).draw(at: NSPoint(x: x + 18, y: 523), withAttributes: detailStyle)

            if completionBadge {
                let badge = NSRect(x: x + 406, y: 540, width: 250, height: 32)
                NSColor(calibratedRed: 0.90, green: 0.97, blue: 0.91, alpha: 1).setFill()
                NSBezierPath(roundedRect: badge, xRadius: 16, yRadius: 16).fill()
                let badgeStyle: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                    .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.45, blue: 0.18, alpha: 1)
                ]
                ("✓ 回复设计评审 已完成" as NSString)
                    .draw(at: NSPoint(x: badge.minX + 18, y: badge.minY + 7), withAttributes: badgeStyle)
            }

            let bezel = NSRect(x: x + 18, y: 58, width: 640, height: 474)
            NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
            NSBezierPath(roundedRect: bezel, xRadius: 10, yRadius: 10).fill()
            let display = NSRect(x: bezel.minX + 7, y: bezel.minY + 7, width: 626, height: 460)
            let image = NSImage(cgImage: screen, size: NSSize(width: 648, height: 480))
            NSGraphicsContext.current?.imageInterpolation = .none
            image.draw(in: display, from: .zero, operation: .copy, fraction: 1)
        }

        drawPanel(
            x: 26,
            label: "同步前 · 4 项待办",
            detail: "墨水屏尚未完成“回复设计评审”",
            screen: beforeScreen,
            completionBadge: false
        )
        drawPanel(
            x: 738,
            label: "本次同步 · 3 项待办",
            detail: "完成事项紧跟现有项目，下一次刷新后移除",
            screen: afterScreen,
            completionBadge: true
        )
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("无法导出完成事项模拟图")
            return
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: url)
    }
}
