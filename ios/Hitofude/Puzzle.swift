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
    /// UIKit may deliver several historical samples with one event. Keep their corners.
    mutating func cells(samples: [CGPoint], width: CGFloat, size: Int) -> [Cell] {
        var result: [Cell] = []
        for point in samples {
            for cell in cells(to: point, width: width, size: size) {
                if result.last != cell { result.append(cell) }
            }
        }
        return result
    }
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

    private static let source: String? = {
        guard let url = Bundle.main.url(forResource: "Generator", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    // The bank contains exact generator output, with the original shareable seed.
    static func prepared(mode: GameMode, index: Int) throws -> (seed: UInt32, puzzle: Puzzle) {
        guard let source, let context = JSContext() else { throw Failure.unavailable }
        context.evaluateScript(source)
        guard let json = context.evaluateScript("JSON.stringify(preparedPuzzles['\(mode.size)-\(mode.difficulty)'].map(entry => entry.seed))")?.toString(),
              let data = json.data(using: .utf8),
              let seeds = try? JSONDecoder().decode([UInt32].self, from: data), !seeds.isEmpty else {
            throw Failure.invalid
        }
        let seed = seeds[max(0, index) % seeds.count]
        return (seed, try generate(mode: mode, seed: seed, timeoutMilliseconds: 0))
    }

    // Create and use each context on the same background thread. No WebView or network needed.
    static func generate(mode: GameMode, seed: UInt32, timeoutMilliseconds: Int = 20000) throws -> Puzzle {
        if mode == .tutorial { return .tutorial }
        guard let source, let context = JSContext() else { throw Failure.unavailable }
        context.evaluateScript(source)
        guard context.exception == nil,
              let function = context.objectForKeyedSubscript("nativePuzzle"),
              let value = function.call(withArguments: [mode.size, mode.difficulty, NSNumber(value: seed), timeoutMilliseconds]),
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
    var text: String { "おかえりなさい" }
}

/// Presentation only: puzzle values, validation and shared seeds stay numeric.
enum PuzzleNotation {
    case numbers, alphabet

    func symbol(_ order: Int) -> String {
        guard self == .alphabet, (1...26).contains(order) else { return String(order) }
        return String(UnicodeScalar(64 + order)!)
    }

    func accessibleClue(_ order: Int) -> String {
        self == .alphabet ? "文字\(symbol(order))、\(order)番目に通るマス" : "数字\(order)"
    }

    func message(_ text: String) -> String {
        guard self == .alphabet else { return text }
        // Position counts remain numbers; only references to the displayed start label change.
        return text.replacingOccurrences(of: "「1」", with: "「A」")
            .replacingOccurrences(of: "1のマスから", with: "Aのマスから")
    }
}


/// Accept only our letter route and bounded, validated message payloads.
struct LetterDestination: Identifiable {
    let id = UUID()
    let webURL: URL

    init?(url: URL) {
        let isWeb = url.scheme == "https" && url.host == "koheisuzuk25252525.github.io" && url.path == "/hitofude/letter.html" && url.port == nil
        let isApp = url.scheme == "hitofude" && url.host == "letter" && (url.path.isEmpty || url.path == "/") && url.port == nil
        guard (isWeb || isApp), url.user == nil, url.password == nil,
              let fragment = url.fragment, fragment.hasPrefix("letter="), fragment.utf8.count <= 8191 else { return nil }
        let encoded = String(fragment.dropFirst(7))
        guard !encoded.isEmpty, encoded.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        struct Payload: Decodable { let v: Int; let text: String; let from: String; let puzzle: Int }
        guard let data = Data(base64Encoded: base64), let payload = try? JSONDecoder().decode(Payload.self, from: data),
              [1, 2].contains(payload.v), (0...3).contains(payload.puzzle),
              !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              payload.text.utf16.count <= 6000, payload.v == 2 || payload.text.count <= 9,
              payload.from.unicodeScalars.count <= 20,
              !(payload.text + payload.from).unicodeScalars.contains(where: { $0.value < 32 && $0.value != 9 || $0.value == 127 }) else { return nil }
        var target = URLComponents(string: "https://koheisuzuk25252525.github.io/hitofude/letter.html")!
        target.queryItems = [URLQueryItem(name: "inApp", value: "1")]
        target.fragment = fragment
        guard let targetURL = target.url else { return nil }
        webURL = targetURL
    }
}
