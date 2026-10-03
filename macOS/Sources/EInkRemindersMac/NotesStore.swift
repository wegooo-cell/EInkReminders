import AppKit
import Foundation

/// Read-only bridge to Apple Notes. Nothing is queried until the NOTE4 enters
/// the Notes view, and attachment bytes are requested only after opening one
/// note. Attachments are intentionally never requested; NOTE4 is a fast,
/// text-only Notes reader.
@MainActor
final class NotesStore {
    enum StoreError: LocalizedError {
        case script(String)

        var errorDescription: String? {
            switch self {
            case .script(let message): return "读取 Apple 备忘录失败：\(message)"
            }
        }
    }

    func fetchSummaries() throws -> [NoteSummary] {
        let separator = "\u{1E}"
        let field = "\u{1F}"
        let source = """
        set rowDelimiter to ASCII character 30
        set fieldDelimiter to ASCII character 31
        set rows to {}
        set cutoffDate to (current date) - (15 * days)
        tell application "Notes"
            repeat with anAccount in accounts
                set recentNotes to every note of anAccount whose modification date is greater than or equal to cutoffDate
                repeat with aNote in recentNotes
                    try
                        set modifiedAt to modification date of aNote
                        -- Plaintext does not load attachment/image bytes. It is
                        -- used only to derive the short list-row excerpt.
                        set noteText to plaintext of aNote
                        if (length of noteText) > 160 then set noteText to text 1 thru 160 of noteText
                        set end of rows to (id of aNote as text) & fieldDelimiter & (name of aNote as text) & fieldDelimiter & (year of modifiedAt as text) & fieldDelimiter & (month of modifiedAt as integer) & fieldDelimiter & (day of modifiedAt as text) & fieldDelimiter & (hours of modifiedAt as text) & fieldDelimiter & (minutes of modifiedAt as text) & fieldDelimiter & noteText
                    end try
                end repeat
            end repeat
        end tell
        set AppleScript's text item delimiters to rowDelimiter
        return rows as text
        """
        let value = try run(source)
        let calendar = Calendar.current
        let now = Date()
        let cutoff7 = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        let rows = value.split(separator: Character(separator), omittingEmptySubsequences: true).compactMap { row -> (NoteSummary, Date)? in
            let fields = row.split(separator: Character(field), omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7,
                  let year = Int(fields[2]), let month = Int(fields[3]),
                  let day = Int(fields[4]), let hour = Int(fields[5]),
                  let minute = Int(fields[6]),
                  let modifiedAt = calendar.date(from: DateComponents(
                    year: year, month: month, day: day, hour: hour, minute: minute
                  )) else { return nil }
            let rawTitle = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = rawTitle.isEmpty ? "未命名备忘录" : rawTitle
            let group: String
            if title.hasPrefix("📌") || title.hasPrefix("置顶：") || title.hasPrefix("置顶:") {
                group = "置顶"
            } else if calendar.isDateInToday(modifiedAt) {
                group = "今天"
            } else if calendar.isDateInYesterday(modifiedAt) {
                group = "昨天"
            } else if modifiedAt >= cutoff7 {
                group = "7天内"
            } else {
                group = "15天内"
            }
            let timeText: String
            if calendar.isDateInToday(modifiedAt) {
                timeText = Self.timeFormatter.string(from: modifiedAt)
            } else if calendar.isDateInYesterday(modifiedAt) {
                timeText = "昨天"
            } else if modifiedAt >= cutoff7 {
                timeText = Self.weekdayFormatter.string(from: modifiedAt)
            } else {
                timeText = Self.shortDateFormatter.string(from: modifiedAt)
            }
            let plaintext = fields.count > 7 ? fields[7...] .joined(separator: " ") : ""
            let preview = previewText(from: plaintext, removingTitle: rawTitle)
            return (NoteSummary(
                id: fields[0],
                title: title,
                modifiedLabel: group,
                modifiedText: timeText,
                previewText: preview
            ), modifiedAt)
        }
        let order = ["置顶": 0, "今天": 1, "昨天": 2, "7天内": 3, "15天内": 4]
        return rows.sorted {
            let lhs = order[$0.0.modifiedLabel, default: 5]
            let rhs = order[$1.0.modifiedLabel, default: 5]
            return lhs == rhs ? $0.1 > $1.1 : lhs < rhs
        }.map(\.0)
    }

    func fetchDocument(_ summary: NoteSummary) throws -> NoteDocument {
        let source = """
        set targetID to "\(escaped(summary.id))"
        tell application "Notes"
            set targetNote to first note whose id is targetID
            return body of targetNote
        end tell
        """
        let html = try run(source)
        let text = plainText(fromHTML: html)
        return NoteDocument(summary: summary, text: text, imageURLs: [])
    }

    private func run(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw StoreError.script("无法建立读取脚本")
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            throw StoreError.script(error[NSAppleScript.errorMessage] as? String ?? error.description)
        }
        return result.stringValue ?? ""
    }

    private func plainText(fromHTML html: String) -> String {
        guard let data = html.data(using: .utf8),
              let value = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else {
            return html
        }
        return value.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func escaped(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func previewText(from plaintext: String, removingTitle title: String) -> String {
        var rows = plaintext
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let first = rows.first, !title.isEmpty,
           first.localizedCaseInsensitiveCompare(title) == .orderedSame {
            rows.removeFirst()
        }
        let value = rows.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "无更多文本" : String(value.prefix(96))
    }

    private static let timeFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.dateFormat = "HH:mm"
        return value
    }()

    private static let weekdayFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.dateFormat = "EEEE"
        return value
    }()

    private static let shortDateFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.dateFormat = "M.d"
        return value
    }()

}
