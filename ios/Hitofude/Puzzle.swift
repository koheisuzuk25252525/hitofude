import Foundation
import JavaScriptCore

struct Cell: Codable, Hashable, Sendable {
    let row: Int
    let column: Int

    func isAdjacent(to other: Cell) -> Bool {
        abs(row - other.row) + abs(column - other.column) == 1
    }
}

/// Sample only consecutive positions inside the board; leaving it breaks the stroke.
struct BoardTrace {
    private var previous: CGPoint?
    mutating func reset() { previous = nil }
    mutating func cells(to point: CGPoint, width: CGFloat, size: Int) -> [Cell] {
        guard width.isFinite, width > 0, size > 0,
              point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.y >= 0, point.x < width, point.y < width else {
            reset(); return []
        }
        let from = previous ?? point
        previous = point
        let step = width / CGFloat(size)
        let samples = max(1, Int(ceil(hypot(point.x - from.x, point.y - from.y) / (step / 4))))
        var cells: [Cell] = []
        for index in 0...samples {
            let t = CGFloat(index) / CGFloat(samples)
            let cell = Cell(row: Int((from.y + (point.y - from.y) * t) / step),
                            column: Int((from.x + (point.x - from.x) * t) / step))
            if cells.last != cell { cells.append(cell) }
        }
        return cells
    }
}

struct Puzzle: Codable, Sendable {
    let size: Int
    let path: [Cell]
    let clues: [Cell: Int]

    static let tutorial = Puzzle(
        size: 4,
        path: [Cell(row: 0, column: 0), Cell(row: 0, column: 1),
               Cell(row: 0, column: 2), Cell(row: 0, column: 3),
               Cell(row: 1, column: 3), Cell(row: 1, column: 2),
               Cell(row: 1, column: 1), Cell(row: 1, column: 0),
               Cell(row: 2, column: 0), Cell(row: 2, column: 1),
               Cell(row: 2, column: 2), Cell(row: 2, column: 3),
               Cell(row: 3, column: 3), Cell(row: 3, column: 2),
               Cell(row: 3, column: 1), Cell(row: 3, column: 0)],
        clues: [Cell(row: 0, column: 0): 1, Cell(row: 1, column: 1): 7,
                Cell(row: 2, column: 2): 11, Cell(row: 3, column: 0): 16]
    )
}

enum GameMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case tutorial, daily, easy, medium, hard, oni
    var id: Self { self }
    var title: String {
        switch self {
        case .tutorial: return "れんしゅう"
        case .daily: return "きょうの1問"
        case .easy: return "やさしい"
        case .medium: return "ふつう"
        case .hard: return "むずかしい"
        case .oni: return "鬼"
        }
    }
    var size: Int {
        switch self {
        case .tutorial: return 4
        case .easy: return 5
        case .daily, .medium: return 6
        case .hard: return 7
        case .oni: return 8
        }
    }
    var difficulty: String {
        switch self {
        case .tutorial, .easy: return "easy"
        case .daily, .medium: return "medium"
        case .hard, .oni: return "hard"
        }
    }
    static func dailySeed(date: Date = Date(), calendar: Calendar = PlayProgress.calendar()) -> UInt32 {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 2026
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let value = year * 10000 + month * 100 + day
        return UInt32(value)
    }
}

enum PuzzleGenerator {
    private struct Payload: Decodable {
        struct Clue: Decodable { let row: Int; let column: Int; let value: Int }
        let size: Int
        let path: [Cell]
        let clues: [Clue]
    }

    enum Failure: LocalizedError {
        case unavailable, invalid
        var errorDescription: String? { "問題を作れませんでした。もう一度お試しください。" }
    }

    // Create and use each context on the same background thread. No WebView or network needed.
    static func generate(mode: GameMode, seed: UInt32) throws -> Puzzle {
        if mode == .tutorial { return .tutorial }
        guard let url = Bundle.main.url(forResource: "Generator", withExtension: "js"),
              let context = JSContext() else { throw Failure.unavailable }
        let source = try String(contentsOf: url, encoding: .utf8)
        context.evaluateScript(source)
        guard context.exception == nil,
              let function = context.objectForKeyedSubscript("nativePuzzle"),
              let value = function.call(withArguments: [mode.size, mode.difficulty, NSNumber(value: seed)]),
              context.exception == nil,
              let json = value.toString(), let data = json.data(using: .utf8) else {
            throw Failure.invalid
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.size == mode.size, payload.path.count == mode.size * mode.size else {
            throw Failure.invalid
        }
        return Puzzle(size: payload.size, path: payload.path,
                      clues: Dictionary(uniqueKeysWithValues: payload.clues.map {
            (Cell(row: $0.row, column: $0.column), $0.value)
        }))
    }
}

/// Friendly, self-reported time challenges. Shared HTTPS links also work with the Web format.
struct Challenge: Codable, Equatable, Sendable {
    let mode: GameMode
    let seed: UInt32
    let seconds: Int

    private static let codes: [String: GameMode] = ["e": .easy, "m": .medium, "h": .hard, "d": .daily, "o": .oni]
    var isValid: Bool { mode != .tutorial && (0...604_800).contains(seconds) }
    var url: URL {
        let code = Self.codes.first(where: { $0.value == mode })?.key ?? "m"
        return URL(string: "https://koheisuzuk25252525.github.io/hitofude/#c-\(code)-\(seed)-\(seconds)")!
    }

    static func parse(_ text: String) -> Challenge? {
        guard text.utf8.count <= 4096 else { return nil }
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            guard let components = URLComponents(string: String(token)),
                  components.scheme == "https", components.host == "koheisuzuk25252525.github.io",
                  components.path == "/hitofude/", components.user == nil, components.password == nil,
                  components.port == nil, components.query == nil,
                  let fragment = components.fragment else { continue }
            let parts = fragment.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0] == "c", let mode = codes[String(parts[1])],
                  !parts[2].isEmpty, !parts[3].isEmpty,
                  parts[2].allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  parts[3].allSatisfy({ $0 >= "0" && $0 <= "9" }),
                  let seed = UInt32(parts[2]), let seconds = Int(parts[3]) else { continue }
            let challenge = Challenge(mode: mode, seed: seed, seconds: seconds)
            if challenge.isValid { return challenge }
        }
        return nil
    }
}

struct PlayProgress: Codable {
    struct Completion: Codable {
        let day: String
        var dailyDay: String?
    }
    private(set) var completions: [String: Completion] = [:]
    private(set) var nightUnlocked = false
    static let monthlyGoal = 10

    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    static func dayKey(_ date: Date, calendar: Calendar = PlayProgress.calendar()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year!, parts.month!, parts.day!)
    }

    func count(in date: Date, calendar: Calendar = PlayProgress.calendar()) -> Int {
        let month = String(Self.dayKey(date, calendar: calendar).prefix(6))
        return completions.values.filter { $0.day.hasPrefix(month) }.count
    }

    func count(on date: Date, calendar: Calendar = PlayProgress.calendar()) -> Int {
        let key = Self.dayKey(date, calendar: calendar)
        return completions.values.filter { $0.day == key }.count
    }

    func dailyCompleted(on date: Date, calendar: Calendar = PlayProgress.calendar()) -> Bool {
        let key = Self.dayKey(date, calendar: calendar)
        return completions.values.contains { $0.dailyDay == key }
    }

    @discardableResult
    mutating func record(mode: GameMode, seed: UInt32, at date: Date,
                         calendar: Calendar = PlayProgress.calendar()) -> Bool {
        guard mode != .tutorial else { return false }
        // Daily and medium can be the exact same board; count that board only once.
        let id = "\(mode.size)-\(mode.difficulty)-\(seed)"
        let key = Self.dayKey(date, calendar: calendar)
        let isNew = completions[id] == nil
        let isDaily = mode == .daily && String(seed) == key
        if isNew { completions[id] = Completion(day: key, dailyDay: isDaily ? key : nil) }
        else if isDaily { completions[id]?.dailyDay = key }
        if count(in: date, calendar: calendar) >= Self.monthlyGoal { nightUnlocked = true }
        return isNew
    }
}


/// A small visual greeting after time away; never blocks play or expires a reward.
enum ReturnGreeting: String, CaseIterable {
    case star, leaf, moon
    var symbol: String {
        switch self {
        case .star: return "sparkles"
        case .leaf: return "leaf.fill"
        case .moon: return "moon.stars.fill"
        }
    }
    var text: String {
        switch self {
        case .star: return "おかえり。小さな星がお出迎え。"
        case .leaf: return "おかえり。ひと息つける場所、空いています。"
        case .moon: return "おかえり。少しだけ、静かな時間を。"
        }
    }
}
