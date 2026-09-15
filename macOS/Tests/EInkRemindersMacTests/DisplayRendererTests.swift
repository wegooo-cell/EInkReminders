import AppKit
import EventKit
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
        func item(
            _ id: String,
            offset: TimeInterval?,
            timed: Bool = true,
            completed: Bool = false
        ) -> ReminderItem {
            ReminderItem(
                syncId: id,
                title: id,
                dueAt: offset.map { now.addingTimeInterval($0) },
                hasDueTime: timed,
                completed: completed,
                priority: 0,
                updatedAt: now
            )
        }
        let alerts = AppModel.pendingAlerts(from: [
            item("future", offset: 3600),
            item("near", offset: -20),
            item("old", offset: -60),
            item("date-only", offset: 7200, timed: false),
            item("done", offset: 60, completed: true),
            item("undated", offset: nil)
        ], now: now)
        XCTAssertEqual(alerts.map(\.syncId), ["near", "future"])
    }

    @MainActor
    func testNote4RebuildsAnUnchangedViewAfterDeviceCacheClear() {
        XCTAssertTrue(AppModel.requiresFrameRebuild(deviceRevision: 0))
        XCTAssertFalse(AppModel.requiresFrameRebuild(deviceRevision: 42))
    }

    func testOnlyFinishedTodayViewUsesCelebration() throws {
        XCTAssertEqual(
            ReminderEmptyState.resolve(
                view: .today,
                visibleCount: 0,
                hasCompletedTodayItems: true
            ),
            .allCompleted
        )
        for view in [DeviceReminderView.scheduled, .all, .completed] {
            XCTAssertEqual(
                ReminderEmptyState.resolve(
                    view: view,
                    visibleCount: 0,
                    hasCompletedTodayItems: true
                ),
                .noItems
            )
        }
        XCTAssertNotEqual(
            try ZectrixDisplayRenderer.render([], view: .today, emptyState: .noItems),
            try ZectrixDisplayRenderer.render([], view: .today, emptyState: .allCompleted)
        )
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
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 11, hour: 23
        ))!
        let tomorrow = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 12, hour: 11
        ))!
        let reminder = ReminderItem(
            syncId: "tomorrow",
            title: "明天上午事项",
            dueAt: tomorrow,
            hasDueTime: true,
            completed: false,
            priority: 0,
            updatedAt: now
        )
        XCTAssertFalse(ReminderStore.belongsToToday(reminder, now: now, calendar: calendar))
        XCTAssertEqual(DisplayRenderer.displayDueLabel(for: reminder, relativeTo: now), "明天 11:00")
        XCTAssertNil(DisplayRenderer.dayPeriod(for: reminder, relativeTo: now))
    }

    func testAllAndScheduledViewsRenderFutureRows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 12, hour: 21
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
        let today = item("今天", day: 12, hour: 22)
        let items = [
            today,
            item("明天", day: 13, hour: 9),
            item("后天", day: 14, hour: 15)
        ]
        for view in [DeviceReminderView.scheduled, .all] {
            XCTAssertNotEqual(
                try ZectrixDisplayRenderer.render([today], view: view, generatedAt: now),
                try ZectrixDisplayRenderer.render(items, view: view, generatedAt: now)
            )
        }
    }

    func testNote4FrameAndPreviewUseNativeResolution() throws {
        let data = try ZectrixDisplayRenderer.render([])
        XCTAssertEqual(data.count, 15_000)
        XCTAssertTrue(data.contains(0xFF))
        XCTAssertTrue(data.contains { $0 != 0xFF })

        let image = try ZectrixDisplayRenderer.previewImage([])
        XCTAssertEqual(image.width, 400)
        XCTAssertEqual(image.height, 300)
    }

    func testNote4SelectedRowsProduceDistinctFrames() throws {
        let now = Date()
        let reminders = [
            ReminderItem(
                syncId: "1",
                title: "第一项",
                completed: false,
                priority: 0,
                updatedAt: now
            ),
            ReminderItem(
                syncId: "2",
                title: "第二项",
                completed: false,
                priority: 0,
                updatedAt: now
            )
        ]
        XCTAssertNotEqual(
            try ZectrixDisplayRenderer.render(reminders, selectedIndex: 0, generatedAt: now),
            try ZectrixDisplayRenderer.render(reminders, selectedIndex: 1, generatedAt: now)
        )
    }

    func testNote4OmitsEmojiWithoutChangingRemainingTitle() throws {
        XCTAssertEqual(
            ZectrixDisplayRenderer.titleWithoutEmoji("🎬 写视频脚本 ✂️"),
            "写视频脚本"
        )
        XCTAssertEqual(ZectrixDisplayRenderer.titleWithoutEmoji("☕️"), "未命名事项")
    }

    @MainActor
    func testLocalCompletionSupportsSeveralItemsAndTwentyRows() throws {
        let now = Date()
        let reminders = (0..<20).map {
            ReminderItem(
                syncId: String($0),
                title: "事项 \($0 + 1)",
                completed: false,
                priority: 0,
                updatedAt: now
            )
        }
        let items = AppModel.itemsMarkingCompleted(reminders, syncIds: ["0", "7", "18"])
        let selected = AppModel.renderSelectionIndex(
            originalIndex: 19,
            items: items,
            view: .all
        )
        XCTAssertEqual(selected, 16)
        XCTAssertEqual(AppModel.nextAvailableOriginalIndex(after: 19, items: items), 1)
        XCTAssertEqual(
            try ZectrixDisplayRenderer.render(
                items,
                selectedIndex: selected,
                view: .all
            ).count,
            ZectrixDisplayRenderer.packedByteCount
        )
    }

    func testCompletedViewShowsSixItemsPerPage() throws {
        let now = Date()
        let completed = (0..<7).map {
            ReminderItem(
                syncId: String($0),
                title: "已完成事项 \($0 + 1)",
                completed: true,
                priority: 0,
                updatedAt: now
            )
        }
        XCTAssertEqual(
            DisplayRenderer.visiblePendingItems(
                completed,
                selectedIndex: 5,
                capacity: 6
            ).count,
            6
        )
        XCTAssertNotEqual(
            try ZectrixDisplayRenderer.render(completed, selectedIndex: 5, view: .completed),
            try ZectrixDisplayRenderer.render(completed, selectedIndex: 6, view: .completed)
        )
    }

    @MainActor
    func testOnlyCompletionOperationsAreCollected() {
        let completed = DeviceOperation(
            sequence: 1,
            type: .setCompleted,
            syncId: "device",
            completed: true
        )
        let reopened = DeviceOperation(
            sequence: 2,
            type: .setCompleted,
            syncId: "reopened",
            completed: false
        )
        let created = DeviceOperation(
            sequence: 3,
            type: .create,
            syncId: "created",
            title: "新事项"
        )
        XCTAssertEqual(
            AppModel.completedOnDeviceIDs(from: [completed, reopened, created]),
            ["device"]
        )
    }

    func testDueLabelsAndDayPeriods() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let reference = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 10, hour: 8
        ))!
        func item(_ hour: Int?) -> ReminderItem {
            ReminderItem(
                syncId: String(hour ?? -1),
                title: "事项",
                dueAt: hour.map {
                    calendar.date(from: DateComponents(
                        year: 2026, month: 9, day: 10, hour: $0
                    ))!
                },
                hasDueTime: hour != nil,
                completed: false,
                priority: 0,
                updatedAt: reference
            )
        }
        XCTAssertEqual(DisplayRenderer.displayDueLabel(for: item(nil), relativeTo: reference), "今天")
        XCTAssertEqual(DisplayRenderer.displayDueLabel(for: item(10), relativeTo: reference), "10:00")
        XCTAssertEqual(DisplayRenderer.dayPeriod(for: item(9), relativeTo: reference), .morning)
        XCTAssertEqual(DisplayRenderer.dayPeriod(for: item(14), relativeTo: reference), .afternoon)
        XCTAssertEqual(DisplayRenderer.dayPeriod(for: item(17), relativeTo: reference), .evening)
    }

    func testAutomaticSyncIntervalsMatchTheUserChoices() {
        XCTAssertEqual(
            AutomaticSyncInterval.allCases.map(\.title),
            ["30 秒", "1 分钟", "10 分钟", "30 分钟", "1 小时"]
        )
    }

    func testExportWebsitePreviewsWhenRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["EINK_NOTE4_WEB_PREVIEW_DIR"] else {
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let generatedAt = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 15, hour: 9
        ))!
        func item(
            _ id: String,
            _ title: String,
            day: Int?,
            hour: Int?,
            completed: Bool = false
        ) -> ReminderItem {
            ReminderItem(
                syncId: id,
                title: title,
                dueAt: day.map {
                    calendar.date(from: DateComponents(
                        year: 2026,
                        month: 9,
                        day: $0,
                        hour: hour
                    ))!
                },
                hasDueTime: hour != nil,
                completed: completed,
                priority: 0,
                updatedAt: generatedAt
            )
        }
        func export(
            _ name: String,
            reminders: [ReminderItem],
            view: DeviceReminderView
        ) throws {
            let image = try ZectrixDisplayRenderer.previewImage(
                reminders,
                view: view,
                generatedAt: generatedAt
            )
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                XCTFail("无法导出 NOTE4 网页预览")
                return
            }
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: url)
        }

        try export("preview-today.png", reminders: [
            item("plan", "整理今日计划", day: nil, hour: nil),
            item("review", "回复设计评审", day: 15, hour: 10),
            item("edit", "剪辑产品视频", day: 15, hour: 14),
            item("walk", "晚间散步", day: 15, hour: 19)
        ], view: .today)
        try export("preview-scheduled.png", reminders: [
            item("meeting", "明天项目会议", day: 16, hour: 11),
            item("dentist", "预约牙医", day: 18, hour: 15),
            item("trip", "整理旅行清单", day: 20, hour: nil)
        ], view: .scheduled)
        try export("preview-completed.png", reminders: [
            item("done-1", "提交项目方案", day: 15, hour: 10, completed: true),
            item("done-2", "回复客户邮件", day: 15, hour: 11, completed: true),
            item("done-3", "更新工作日志", day: 15, hour: 17, completed: true)
        ], view: .completed)
    }
}
