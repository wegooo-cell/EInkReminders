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
        for view in [DeviceReminderView.notes, .all, .completed] {
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
        let model = AppModel(defaults: defaults)
        model.deviceURL = "%"
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(model.statusText, "同步失败：设备地址无效")
    }

    @MainActor
    func testMissedEventKitNotificationIsDetectedFromLocalSnapshot() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let newItem = ReminderItem(
            syncId: "from-iphone", title: "iPhone 新事项",
            dueAt: now.addingTimeInterval(3600), hasDueTime: true,
            completed: false, priority: 0, updatedAt: now
        )
        let snapshot = ReminderViewSnapshot(
            items: [newItem], totalCount: 1,
            emptyState: .noItems, alertCandidates: [newItem]
        )
        XCTAssertTrue(AppModel.hasMissedReminderChanges(
            snapshot, renderedItems: [], renderedCount: 0,
            renderedEmptyState: .noItems, alertSignatures: [], now: now
        ))
        let signature = "from-iphone|\(Int64(newItem.dueAt!.timeIntervalSince1970 * 1_000))|iPhone 新事项"
        XCTAssertFalse(AppModel.hasMissedReminderChanges(
            snapshot, renderedItems: [newItem], renderedCount: 1,
            renderedEmptyState: .noItems, alertSignatures: [signature], now: now
        ))
    }

    func testStandbyTextPatchesHaveNativeBitmaps() throws {
        let title = try ZectrixDisplayRenderer.renderStandbyTitlePatch("写视频脚本")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 13))!
        let dueAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 14, minute: 30))!
        let due = try ZectrixDisplayRenderer.renderStandbyDuePatch(dueAt, now: now)
        XCTAssertEqual(title.count, 112 * 22 / 8)
        XCTAssertEqual(due.count, 112 * 22 / 8)
        XCTAssertTrue(title.contains { $0 != 0xFF })
        XCTAssertTrue(due.contains { $0 != 0xFF })
        if let directory = ProcessInfo.processInfo.environment["EINK_STANDBY_PATCH_PREVIEW_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try title.write(to: url.appendingPathComponent("standby-title.bin"))
            try due.write(to: url.appendingPathComponent("standby-due.bin"))
        }
    }

    func testPhotoStandbyWeatherAndReminderPatchesMatchFirmwareSizes() throws {
        let weather = try ZectrixDisplayRenderer.renderWeatherPatch(city: "广州", celsius: 29)
        let longWeather = try ZectrixDisplayRenderer.renderWeatherPatch(city: "San Francisco", celsius: -12)
        let reminder = try ZectrixDisplayRenderer.renderPhotoReminderPatch("写视频脚本")
        XCTAssertEqual(weather.count, 190 * 140 / 8)
        XCTAssertEqual(longWeather.count, weather.count)
        XCTAssertEqual(reminder.count, 184 * 22 / 8)
        XCTAssertTrue(weather.contains { $0 != 0 })
        XCTAssertTrue(reminder.contains { $0 != 0xFF })
        if let directory = ProcessInfo.processInfo.environment["EINK_PHOTO_STANDBY_PATCH_DIR"] {
            let base = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try weather.write(to: base.appendingPathComponent("weather.bin"))
            try reminder.write(to: base.appendingPathComponent("reminder.bin"))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 13))!
            let dueAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 14, minute: 30))!
            let due = try ZectrixDisplayRenderer.renderStandbyDuePatch(dueAt, now: now)
            try due.write(to: base.appendingPathComponent("due.bin"))
        }
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
        XCTAssertEqual(
            DisplayRenderer.displayDueLabel(
                for: reminder,
                relativeTo: now,
                calendar: calendar
            ),
            "明天 11:00"
        )
        XCTAssertNil(
            DisplayRenderer.dayPeriod(
                for: reminder,
                relativeTo: now,
                calendar: calendar
            )
        )
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
        for view in [DeviceReminderView.all] {
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
        let snoozed = DeviceOperation(
            sequence: 3,
            type: .setDueAt,
            syncId: "snoozed",
            dueAtEpochMs: 1_800_000_300_000
        )
        XCTAssertEqual(
            AppModel.completedOnDeviceIDs(from: [completed, reopened, snoozed]),
            ["device"]
        )
    }

    func testTodayViewOrderMatchesScreenOrder() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!

        func item(_ id: String, dueAt: Date?, timed: Bool) -> ReminderItem {
            ReminderItem(
                syncId: id,
                title: id,
                dueAt: dueAt,
                hasDueTime: timed,
                completed: false,
                priority: 0,
                updatedAt: now
            )
        }

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
        let tenInTheMorning = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now)
        let sevenInTheEvening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now)
        let fetched = [
            item("overdue", dueAt: yesterday, timed: true),
            item("date-only", dueAt: calendar.startOfDay(for: now), timed: false),
            item("morning", dueAt: tenInTheMorning, timed: true),
            item("evening", dueAt: sevenInTheEvening, timed: true),
            item("undated", dueAt: nil, timed: false)
        ]

        // 屏幕先画不属于时段分组的事项，再画上午、下午、今晚；按键移动的列表顺序必须一致。
        XCTAssertEqual(
            ReminderStore.orderedLikeTodayScreen(fetched, now: now).map(\.syncId),
            ["overdue", "date-only", "undated", "morning", "evening"]
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

        // 传入固定时区的日历，结果不随本机时区变化。
        func label(_ hour: Int?) -> String {
            DisplayRenderer.displayDueLabel(
                for: item(hour),
                relativeTo: reference,
                calendar: calendar
            )
        }
        func period(_ hour: Int) -> DisplayRenderer.DayPeriod? {
            DisplayRenderer.dayPeriod(
                for: item(hour),
                relativeTo: reference,
                calendar: calendar
            )
        }

        XCTAssertEqual(label(nil), "今天")
        XCTAssertEqual(label(10), "10:00")

        XCTAssertEqual(period(9), .morning)
        XCTAssertEqual(period(14), .afternoon)
        XCTAssertEqual(period(17), .evening)
    }

    func testNotesRendererUsesNativeFrameSize() throws {
        let data = try ZectrixDisplayRenderer.renderNotesList([
            NoteSummary(id: "1", title: "项目资料", modifiedLabel: "今天")
        ])
        XCTAssertEqual(data.count, 15_000)
    }

    func testSelectedRowStaysVisibleAfterFiveLocalCompletions() throws {
        let now = Date()
        let reminders = (0..<7).map {
            ReminderItem(
                syncId: String($0),
                title: "事项 \($0 + 1)",
                completed: $0 < 5,
                priority: 0,
                updatedAt: now
            )
        }

        // 本地排队完成 5 项后，带选中与不带选中的画面必须不同，选中行才看得见。
        XCTAssertNotEqual(
            try ZectrixDisplayRenderer.render(
                reminders,
                selectedIndex: 0,
                view: .all,
                generatedAt: now
            ),
            try ZectrixDisplayRenderer.render(
                reminders,
                selectedIndex: nil,
                view: .all,
                generatedAt: now
            )
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
        ], view: .all)
        try export("preview-completed.png", reminders: [
            item("done-1", "提交项目方案", day: 15, hour: 10, completed: true),
            item("done-2", "回复客户邮件", day: 15, hour: 11, completed: true),
            item("done-3", "更新工作日志", day: 15, hour: 17, completed: true)
        ], view: .completed)
    }

    func testExportApprovalTodayPreviewWhenRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["EINK_NOTE4_APPROVAL_PREVIEW_DIR"] else { return }
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let titles = ["上午·提交项目方案", "下午·写视频脚本", "今晚·整理资料"]
        let hours = [10, 14, 20]
        let reminders = zip(titles, hours).enumerated().map { index, pair in
            ReminderItem(
                syncId: "approval-\(index)", title: pair.0,
                dueAt: calendar.date(byAdding: .hour, value: pair.1, to: start),
                hasDueTime: true, completed: false, priority: 0, updatedAt: now
            )
        }
        let image = try ZectrixDisplayRenderer.previewImage([reminders[1]], view: .today, generatedAt: now)
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        let destination = URL(fileURLWithPath: directory).appendingPathComponent("03-today-sections.png")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: destination)
        let populated = try ZectrixDisplayRenderer.previewImage(reminders, view: .today, generatedAt: now)
        let populatedPNG = NSBitmapImageRep(cgImage: populated).representation(using: .png, properties: [:])!
        try populatedPNG.write(to: URL(fileURLWithPath: directory).appendingPathComponent("03b-today-populated.png"))

        func exportCalendar(_ name: String, monthOffset: Int, selectedDay: Int) throws {
            let packed = try ZectrixDisplayRenderer.renderCalendar(
                reminders, monthOffset: monthOffset, selectedDay: selectedDay,
                selectingDay: true, dayDetail: false, detailPage: 0, generatedAt: now
            )
            let bits = [UInt8](packed)
            let pixels = (0..<(400 * 300)).map { bit -> UInt8 in
                bits[bit / 8] & UInt8(0x80 >> (bit % 8)) == 0 ? 0 : 255
            }
            let provider = CGDataProvider(data: Data(pixels) as CFData)!
            let image = CGImage(width: 400, height: 300, bitsPerComponent: 8,
                                bitsPerPixel: 8, bytesPerRow: 400,
                                space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false,
                                intent: .defaultIntent)!
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
        }
        try exportCalendar("07-calendar-last-day.png", monthOffset: 0, selectedDay: 30)
        try exportCalendar("08-calendar-next-month.png", monthOffset: 1, selectedDay: 1)
    }
}
