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
    case scheduled
    case all
    case completed

    var title: String {
        switch self {
        case .today: return "今天"
        case .scheduled: return "计划"
        case .all: return "全部"
        case .completed: return "完成"
        }
    }
}

struct ReminderViewCounts: Codable, Equatable, Sendable {
    let today: Int
    let scheduled: Int
    let all: Int
    let completed: Int
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
}

struct DeviceOperationsResponse: Codable, Sendable {
    let operations: [DeviceOperation]
}

struct DeviceOperation: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case create
        case setCompleted
        case setDueAt
    }

    let sequence: UInt64
    let type: Kind
    let syncId: String
    var appleId: String?
    var title: String?
    var notes: String?
    var dueAt: Date?
    var dueAtEpochMs: Int64?
    var completed: Bool?

    var id: UInt64 { sequence }
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
