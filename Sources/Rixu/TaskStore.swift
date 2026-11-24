import Foundation
import Observation

struct Subtask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var separate = false
    var completedAt: Date?
}

struct WorkItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var start: Date?
    var end: Date?
    var completedAt: Date?
    var subtasks: [Subtask] = []

    var canComplete: Bool { subtasks.allSatisfy { $0.completedAt != nil } }
    var completedCount: Int { subtasks.filter { $0.completedAt != nil }.count }

    func overdue(at date: Date) -> Bool {
        completedAt == nil && (end.map { $0 < date } ?? false)
    }

    func scheduled(in day: DateInterval) -> Bool {
        guard let start, let end else { return false }
        return start < day.end && end >= day.start
    }
}

struct ManualDone: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
}

struct DoneEntry: Identifiable, Equatable {
    enum Source: Equatable {
        case task
        case subtask(parent: UUID, title: String)
        case manual
    }

    let id: UUID
    let title: String
    let date: Date
    let source: Source
    var details: [String] = []
}

enum WorkCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }

    @MainActor private static let formatters = NSCache<NSString, DateFormatter>()

    @MainActor static func label(_ date: Date, _ format: String) -> String {
        let calendar = calendar
        let zone = TimeZone.current
        let key = (format + "|" + zone.identifier) as NSString
        if let cached = formatters.object(forKey: key) { return cached.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = calendar.locale
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.dateFormat = format
        formatters.setObject(formatter, forKey: key)
        return formatter.string(from: date)
    }

    static func move(_ day: Date, by amount: Int, component: Calendar.Component = .day) -> Date {
        calendar.date(byAdding: component, value: amount, to: day) ?? day
    }

    static func monthStart(_ day: Date) -> Date {
        calendar.dateInterval(of: .month, for: day)?.start ?? day
    }

    static func monthGridDays(_ month: Date) -> [Date] {
        let calendar = calendar
        let first = monthStart(month)
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        return (0..<42).map { move(first, by: $0 - offset) }
    }

    static func onDay(_ day: Date, now: Date = .now) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}

@MainActor @Observable
final class TaskStore {
    private struct Snapshot: Codable {
        var tasks: [WorkItem] = []
        var manual: [ManualDone] = []
    }

    @ObservationIgnored private let file: URL
    @ObservationIgnored private var loadFailed = false
    private var snapshot = Snapshot()
    private(set) var pending: [WorkItem] = []
    private(set) var done: [DoneEntry] = []
    var message: String?
    var tasks: [WorkItem] { snapshot.tasks }

    init(file: URL) {
        self.file = file
        do {
            load(try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file)))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        } catch {
            loadFailed = true
            message = "无法读取本地清单。原数据已保留。"
        }
    }

    private func load(_ next: Snapshot) {
        var result = next.manual.map {
            DoneEntry(id: $0.id, title: $0.title, date: $0.date, source: .manual)
        }
        var remaining: [WorkItem] = []
        for task in next.tasks {
            if let date = task.completedAt {
                result.append(DoneEntry(id: task.id, title: task.title, date: date, source: .task,
                                        details: task.subtasks.filter { !$0.separate }.map(\.title)))
            } else {
                remaining.append(task)
            }
            for subtask in task.subtasks where subtask.separate {
                if let date = subtask.completedAt {
                    result.append(DoneEntry(id: subtask.id, title: subtask.title, date: date,
                                            source: .subtask(parent: task.id, title: task.title)))
                }
            }
        }
        snapshot = next
        pending = remaining
        done = result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }

    func done(in interval: DateInterval) -> [DoneEntry] {
        Array(done[doneRange(in: interval)])
    }

    func doneCount(in interval: DateInterval) -> Int { doneRange(in: interval).count }

    private func doneRange(in interval: DateInterval) -> Range<Int> {
        firstDone(before: interval.end)..<firstDone(before: interval.start)
    }

    // The index is sorted newest first. A strict bound keeps the interval end exclusive.
    private func firstDone(before date: Date) -> Int {
        var lower = 0
        var upper = done.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if done[middle].date >= date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    func done(on day: Date) -> [DoneEntry] {
        guard let interval = WorkCalendar.calendar.dateInterval(of: .day, for: day) else { return [] }
        return done(in: interval)
    }

    func reportMaterial(in interval: DateInterval) -> String {
        let entries = done(in: interval)
        let parents = Set(entries.filter { $0.source == .task }.map(\.id))
        var related: [UUID: [DoneEntry]] = [:]
        for entry in entries {
            if case let .subtask(parent, _) = entry.source, parents.contains(parent) {
                related[parent, default: []].append(entry)
            }
        }
        return entries.compactMap { entry -> String? in
            let prefix = WorkCalendar.label(entry.date, "M月d日")
            if case let .subtask(parent, _) = entry.source, parents.contains(parent) { return nil }
            let steps = entry.details.map { "  - \($0)" }
            let deliverables = related[entry.id, default: []].map {
                "  - \(WorkCalendar.label($0.date, "M月d日")) · \($0.title)"
            }
            return (["- \(prefix) · \(entry.title)"] + steps + deliverables).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    @discardableResult
    func save(_ task: WorkItem) -> Bool {
        var next = snapshot
        if let index = next.tasks.firstIndex(where: { $0.id == task.id }) {
            next.tasks[index] = task
        } else {
            next.tasks.insert(task, at: 0)
        }
        return commit(next)
    }

    func complete(_ task: WorkItem, at date: Date = .now) {
        guard var current = tasks.first(where: { $0.id == task.id }),
              current.completedAt == nil, current.canComplete else { return }
        current.completedAt = date
        save(current)
    }

    func toggle(_ subtask: Subtask, in task: WorkItem, at date: Date = .now) {
        guard var current = tasks.first(where: { $0.id == task.id }),
              current.completedAt == nil,
              let index = current.subtasks.firstIndex(where: { $0.id == subtask.id }) else { return }
        current.subtasks[index].completedAt = current.subtasks[index].completedAt == nil ? date : nil
        save(current)
    }

    @discardableResult
    func save(_ entry: ManualDone) -> Bool {
        var next = snapshot
        if let index = next.manual.firstIndex(where: { $0.id == entry.id }) {
            next.manual[index] = entry
        } else {
            next.manual.append(entry)
        }
        return commit(next)
    }

    func manualEntry(_ id: UUID) -> ManualDone? {
        snapshot.manual.first { $0.id == id }
    }

    func restore(_ entry: DoneEntry) {
        switch entry.source {
        case .manual: break
        case .task:
            guard var task = tasks.first(where: { $0.id == entry.id }) else { return }
            task.completedAt = nil
            save(task)
        case let .subtask(parent, _):
            guard var task = tasks.first(where: { $0.id == parent }),
                  let index = task.subtasks.firstIndex(where: { $0.id == entry.id }) else { return }
            task.completedAt = nil
            task.subtasks[index].completedAt = nil
            save(task)
        }
    }

    func remove(task id: UUID) {
        var next = snapshot
        next.tasks.removeAll { $0.id == id }
        commit(next)
    }

    func remove(manual id: UUID) {
        var next = snapshot
        next.manual.removeAll { $0.id == id }
        commit(next)
    }

    @discardableResult
    private func commit(_ next: Snapshot) -> Bool {
        guard !loadFailed else {
            message = "本地清单无法读取，暂时无法保存修改。"
            return false
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            load(next)
            message = nil
            return true
        } catch {
            message = "无法保存到本机，请检查可用空间和文件权限。"
            return false
        }
    }
}
