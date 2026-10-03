import Foundation

struct ReminderItem: Codable, Identifiable, Equatable, Sendable {
    let syncId: String
    var appleId: String? = nil
    var title: String
    var notes: String?
    var dueAt: Date?
    var hasDueTime: Bool = false
    var completed: Bool
    var priority: Int
    var updatedAt: Date

    var id: String { syncId }
}

enum DeviceReminderView: String, Codable, CaseIterable, Sendable {
    case today
    case notes
    case all
    case completed
    case planned
    case calendar

    var title: String {
        switch self {
        case .today: return "今天"
        case .notes: return "备忘录"
        case .all: return "全部"
        case .completed: return "完成"
        case .planned: return "计划"
        case .calendar: return "日历"
        }
    }
}

struct ReminderViewCounts: Codable, Equatable, Sendable {
    let today: Int
    let notes: Int
    let all: Int
    let completed: Int
    let planned: Int?
}

struct ReminderViewSnapshot: Sendable {
    let items: [ReminderItem]
    let totalCount: Int
    let emptyState: ReminderEmptyState
    let alertCandidates: [ReminderItem]
}

enum ReminderEmptyState: String, Sendable {
    case noItems
    case allCompleted

    var message: String {
        switch self {
        case .noItems: return "目前没有事项"
        case .allCompleted: return "都忙完了玩去吧"
        }
    }

    static func resolve(
        view: DeviceReminderView,
        visibleCount: Int,
        hasCompletedTodayItems: Bool
    ) -> ReminderEmptyState {
        // Only Today's empty view gets the celebratory message, and only if
        // this list had a task belonging to Today that is now completed.
        guard visibleCount == 0,
              view == .today,
              hasCompletedTodayItems else { return .noItems }
        return .allCompleted
    }
}

struct DeviceSnapshot: Codable, Sendable {
    let revision: UInt64

    /// 快照所属的视图；与设备当前视图不一致时设备拒收，同步期间切换视图不会显示旧视图的内容。
    let view: DeviceReminderView

    let reminders: [DeviceSnapshotItem]
    let viewCounts: ReminderViewCounts?
    let currentViewCount: Int?
    let replaceDisplay: Bool?
    let sentAtEpochMs: Int64?
    let timeZoneOffsetMinutes: Int?
    let todayDay: Int?
    let todayMonth: Int?
    let todayYear: Int?
    /// Gregorian dates with reminders, encoded as YYYYMMDD for the device calendar.
    let calendarDateKeys: [Int]?
    let alerts: [DeviceAlert]?
}

/// 快照中的事项只带固件用到的字段，标题、备注等内容不以明文上传。
struct DeviceSnapshotItem: Codable, Sendable {
    let syncId: String
    let appleId: String?
    let completed: Bool
}

struct DeviceAlert: Codable, Sendable {
    let syncId: String
    let appleId: String?
    let dueAtEpochMs: Int64
    /// 280×78, 1 bpp, MSB first; only black content pixels are overlaid.
    let bitmap: String
    /// 112×22 native 1-bit pixel-font labels for the approved StandBy views.
    let standbyTitleBitmap: String?
    let standbyDueBitmap: String?
    /// 184×22 pixel-font line for the photo/weather StandBy screen.
    let photoReminderBitmap: String?
}

struct DeviceStatus: Codable, Sendable {
    let deviceId: String
    var firmwareVersion: String?
    let revision: UInt64
    let operationCount: Int
    let width: Int
    let height: Int
    var pixelFormat: String?
    var syncRequested: Bool?

    /// 当前同步请求的序号；确认同步时原样回传，设备只清除这一次请求。
    var syncRequestId: UInt64?

    var syncRequestAgeMs: Int?
    var view: DeviceReminderView?
    var selectedIndex: Int?
    var displayRequested: Bool?
    var noteDetail: Bool?
    var noteOpenRequested: Bool?
    var notePage: Int?
    var calendarMonthOffset: Int?
    var calendarSelectedDay: Int?
    var calendarSelectingDay: Bool?
    var calendarDayDetail: Bool?
    var calendarDetailPage: Int?
    var weatherCity: String?
    var weatherLatitude: Double?
    var weatherLongitude: Double?
    var weatherLocationVersion: UInt32?
}

struct NoteSummary: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let modifiedLabel: String
    let modifiedText: String
    let previewText: String

    init(
        id: String,
        title: String,
        modifiedLabel: String,
        modifiedText: String = "",
        previewText: String = ""
    ) {
        self.id = id
        self.title = title
        self.modifiedLabel = modifiedLabel
        self.modifiedText = modifiedText
        self.previewText = previewText
    }
}

struct NoteDocument: Equatable, Sendable {
    let summary: NoteSummary
    let text: String
    let imageURLs: [URL]
}

struct DeviceOperationsResponse: Codable, Sendable {
    let operations: [DeviceOperation]
}

struct DeviceOperation: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case setCompleted
        case setDueAt
    }

    let sequence: UInt64
    let type: Kind
    let syncId: String
    var appleId: String?
    var dueAtEpochMs: Int64?
    var completed: Bool?

    var id: UInt64 { sequence }
}

/// 暂时无法写回 Apple 提醒事项的设备操作。Mac 会持久化保存并在后续同步中继续重试，
/// 因此一条失败操作不会卡住后续同步，也不会因为确认设备队列而丢失。
struct DeferredOperation: Codable, Sendable {
    let operation: DeviceOperation
    var message: String
    var attempts: Int
}

/// 面向用户的同步诊断。除了错误标题，还明确说明发生位置与下一步处理办法。
struct SyncFailure: Sendable {
    let title: String
    let reason: String
    let suggestion: String
    let technicalDetail: String?
}

enum WireCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
