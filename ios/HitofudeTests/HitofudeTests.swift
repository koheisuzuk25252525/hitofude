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

    @MainActor
    func testSessionRestoresRouteHintsAndExcludesTimeAway() async throws {
        let name = "hitofude-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var date = Date(timeIntervalSince1970: 1_000)
        let game = GameModel(defaults: defaults, now: { date })
        await game.load(.easy, seed: 1000)
        let puzzle = try XCTUnwrap(game.puzzle)
        game.step(puzzle.path[0]); game.step(puzzle.path[1]); game.hint()
        date = date.addingTimeInterval(12)
        game.setActive(false)
        XCTAssertEqual(game.elapsed(at: date), 12, accuracy: 0.001)
        date = date.addingTimeInterval(3600)
        XCTAssertEqual(game.elapsed(at: date), 12, accuracy: 0.001)
        game.step(puzzle.path[2]) // Inactive scenes cannot accept moves.
        XCTAssertEqual(game.route.count, 2)
        let restored = GameModel(defaults: defaults, now: { date })
        await restored.startInitialGame()
        XCTAssertEqual(restored.route, game.route)
        XCTAssertEqual(restored.puzzle?.path, puzzle.path)
        XCTAssertEqual(restored.seed, 1000)
        XCTAssertEqual(restored.hintsLeft, 2)
        XCTAssertEqual(restored.highlighted, puzzle.path[2])
        XCTAssertEqual(restored.elapsed(at: date), 12, accuracy: 0.001)
        date = date.addingTimeInterval(3)
        XCTAssertEqual(restored.elapsed(at: date), 15, accuracy: 0.001)
        restored.setActive(false); restored.setActive(false)
        date = date.addingTimeInterval(5)
        restored.setActive(true); restored.setActive(true)
        XCTAssertEqual(restored.elapsed(at: date), 15, accuracy: 0.001)
        restored.undo()
        let afterUndo = GameModel(defaults: defaults, now: { date })
        await afterUndo.startInitialGame()
        XCTAssertEqual(afterUndo.route.count, 1)
        afterUndo.reset()
        let afterReset = GameModel(defaults: defaults, now: { date })
        await afterReset.startInitialGame()
        XCTAssertTrue(afterReset.route.isEmpty)
        XCTAssertEqual(afterReset.hintsLeft, 3)
        XCTAssertEqual(afterReset.elapsed(at: date), 0)
    }

    @MainActor
    func testEveryMoveIsSavedWithoutBackgroundNotification() async throws {
        let name = "hitofude-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let game = GameModel(defaults: defaults)
        await game.load(.tutorial)
        for cell in Puzzle.tutorial.path.prefix(5) { game.step(cell) }
        let restored = GameModel(defaults: defaults)
        await restored.startInitialGame()
        XCTAssertEqual(restored.route, Array(Puzzle.tutorial.path.prefix(5)))
        XCTAssertFalse(restored.isFinished)
        for cell in Puzzle.tutorial.path.dropFirst(5) { restored.step(cell) }
        let completed = GameModel(defaults: defaults)
        await completed.startInitialGame()
        XCTAssertTrue(completed.isFinished)
        XCTAssertEqual(completed.route.count, 16)
    }

    @MainActor
    func testCorruptOrInvalidSessionFallsBackSafely() async throws {
        let name = "hitofude-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("invalid JSON".utf8), forKey: "hitofude.session.v1")
        let game = GameModel(defaults: defaults)
        await game.startInitialGame()
        XCTAssertEqual(game.mode, .tutorial)
        let valid = try XCTUnwrap(defaults.data(forKey: "hitofude.session.v1"))
        for change in ["version", "route", "elapsed", "hintsLeft"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
            switch change {
            case "version": object[change] = 999
            case "route": object[change] = [["row": 100, "column": 100]]
            case "elapsed": object[change] = -5
            default: object[change] = 99
            }
            defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "hitofude.session.v1")
            let fallback = GameModel(defaults: defaults)
            await fallback.startInitialGame()
            XCTAssertEqual(fallback.mode, .tutorial)
            XCTAssertTrue(fallback.route.isEmpty)
            XCTAssertEqual(fallback.hintsLeft, 3)
        }
    }

    func testChallengeRoundTripAndRejectsInvalidLinks() {
        for mode in GameMode.allCases.filter({ $0 != .tutorial }) {
            let challenge = Challenge(mode: mode, seed: UInt32.max, seconds: 42)
            XCTAssertEqual(Challenge.parse(challenge.url.absoluteString), challenge)
            XCTAssertEqual(Challenge.parse("このタイムに挑戦！\n\(challenge.url.absoluteString)"), challenge)
        }
        let base = "https://koheisuzuk25252525.github.io/hitofude/"
        for link in ["\(base)#c-x-1-20", "\(base)#c-e-4294967296-20",
                     "\(base)#c-e-1--20", "\(base)#c-e-1-604801",
                     "\(base)#c-e--20", "\(base)#c-e-1-nan",
                     "\(base)#c-e-1-20-extra", "\(base)?x=1#c-e-1-20",
                     "https://example.com/hitofude/#c-e-1-20",
                     "https://koheisuzuk25252525.github.io.evil.example/hitofude/#c-e-1-20",
                     "file:///hitofude/#c-e-1-20", String(repeating: "x", count: 4097)] {
            XCTAssertNil(Challenge.parse(link), link)
        }
        XCTAssertNotNil(Challenge.parse("\(base)#c-e-0-0"))
    }

    @MainActor
    func testChallengeRestoresRivalAndJudgesRoundedTimes() async throws {
        let name = "hitofude-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var date = Date(timeIntervalSince1970: 1_000)
        let challenge = Challenge(mode: .easy, seed: 1000, seconds: 10)
        let game = GameModel(defaults: defaults, now: { date })
        await game.load(challenge.mode, seed: challenge.seed, rival: challenge)
        let puzzle = try XCTUnwrap(game.puzzle)
        game.step(puzzle.path[0])
        game.setActive(false)
        let restored = GameModel(defaults: defaults, now: { date })
        await restored.startInitialGame()
        XCTAssertEqual(restored.rival, challenge)
        date = date.addingTimeInterval(9.6)
        for cell in puzzle.path.dropFirst() { restored.step(cell) }
        XCTAssertEqual(restored.verdict, "引き分け！")
        XCTAssertEqual(restored.challenge?.seconds, 10)
        let finished = GameModel(defaults: defaults, now: { date })
        await finished.startInitialGame()
        XCTAssertEqual(finished.verdict, "引き分け！")
        date = date.addingTimeInterval(100)
        XCTAssertEqual(finished.elapsed(at: date), 9.6, accuracy: 0.001)
        for (seconds, expected) in [(9.0, "あなたの勝ち！"), (11.0, "相手の勝ち。もう一度挑戦しよう！")] {
            await finished.load(challenge.mode, seed: challenge.seed, rival: challenge)
            let fresh = try XCTUnwrap(finished.puzzle)
            finished.step(fresh.path[0])
            date = date.addingTimeInterval(seconds)
            for cell in fresh.path.dropFirst() { finished.step(cell) }
            XCTAssertEqual(finished.verdict, expected)
        }
    }

}
