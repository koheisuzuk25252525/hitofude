import Foundation
import JavaScriptCore

struct Cell: Codable, Hashable, Sendable {
    let row: Int
    let column: Int

    func isAdjacent(to other: Cell) -> Bool {
        abs(row - other.row) + abs(column - other.column) == 1
    }
}

struct Puzzle: Sendable {
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

enum GameMode: String, CaseIterable, Identifiable, Sendable {
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
    static func dailySeed(date: Date = Date(), calendar: Calendar = .current) -> UInt32 {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return UInt32((parts.year ?? 2026) * 10000 + (parts.month ?? 1) * 100 + (parts.day ?? 1))
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
