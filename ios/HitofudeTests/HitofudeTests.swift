import XCTest
import JavaScriptCore
@testable import Hitofude

final class HitofudeTests: XCTestCase {
    func testEveryDifficultyHasUniqueSolutionAndStableSeed() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Generator", withExtension: "js"))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        for mode in [GameMode.easy, .medium, .hard, .oni] {
            for offset in 0..<(mode == .oni ? 2 : 5) {
                let seed = UInt32(1000 + offset)
                let puzzle = try PuzzleGenerator.generate(mode: mode, seed: seed)
                let repeated = try PuzzleGenerator.generate(mode: mode, seed: seed)
                XCTAssertEqual(puzzle.path, repeated.path)
                XCTAssertEqual(puzzle.clues, repeated.clues)
                XCTAssertEqual(Set(puzzle.path).count, mode.size * mode.size)
                XCTAssertEqual(puzzle.clues[puzzle.path.first!], 1)
                XCTAssertEqual(puzzle.clues[puzzle.path.last!], mode.size * mode.size)
                for pair in zip(puzzle.path, puzzle.path.dropFirst()) {
                    XCTAssertTrue(pair.0.isAdjacent(to: pair.1))
                }
                let clues = puzzle.clues.map { "['\($0.key.row),\($0.key.column)',\($0.value)]" }.joined(separator: ",")
                let result = context.evaluateScript("countSolutions(\(mode.size),\(mode.size),new Map([\(clues)]))")
                XCTAssertNil(context.exception)
                XCTAssertEqual(result?.toInt32(), 1, "\(mode) seed \(seed)")
            }
        }
    }

    func testDailySeedUsesLocalCalendarDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))!
        XCTAssertEqual(GameMode.dailySeed(date: date, calendar: calendar), 20261021)
    }

    @MainActor
    func testTutorialRejectsInvalidMovesAndCompletes() async throws {
        let name = "hitofude-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let game = GameModel(defaults: defaults)
        await game.load(.tutorial)
        game.step(Cell(row: 0, column: 1)) // Cannot start away from 1.
        XCTAssertTrue(game.route.isEmpty)
        game.step(Cell(row: 0, column: 0))
        game.step(Cell(row: 1, column: 1)) // Diagonal.
        XCTAssertEqual(game.route.count, 1)
        game.step(Cell(row: 1, column: 0))
        game.step(Cell(row: 1, column: 1)) // Clue 7 cannot be third.
        XCTAssertEqual(game.route.count, 2)
        game.step(Cell(row: 0, column: 0)) // Backtrack.
        XCTAssertEqual(game.route.count, 1)
        game.reset()
        for cell in Puzzle.tutorial.path { game.step(cell) }
        XCTAssertTrue(game.isFinished)
        XCTAssertTrue(defaults.bool(forKey: "hitofude.tutorialCompleted"))
        XCTAssertEqual(game.route.count, 16)
        game.undo()
        XCTAssertEqual(game.route.count, 16)
        game.reset()
        XCTAssertFalse(game.isFinished)
        XCTAssertNil(game.startedAt)
        XCTAssertTrue(game.route.isEmpty)
    }

    @MainActor
    func testHintAndUndo() async throws {
        let name = "hitofude-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let game = GameModel(defaults: defaults)
        await game.load(.easy, seed: 1000)
        let puzzle = try XCTUnwrap(game.puzzle)
        game.hint()
        XCTAssertEqual(game.highlighted, puzzle.path.first)
        XCTAssertEqual(game.hintsLeft, 2)
        game.step(puzzle.path[0])
        game.step(puzzle.path[1])
        game.undo()
        XCTAssertEqual(game.route, [puzzle.path[0]])
        game.hint()
        XCTAssertEqual(game.highlighted, puzzle.path[1])
        XCTAssertEqual(game.hintsLeft, 1)
    }
}
