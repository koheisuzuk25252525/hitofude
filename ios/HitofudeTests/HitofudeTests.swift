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
        XCTAssertFalse(completed.isFinished)
        XCTAssertEqual(completed.mode, .easy)
        XCTAssertTrue(completed.route.isEmpty)
    }

    @MainActor
    func testCorruptOrInvalidSessionFallsBackSafely() async throws {
        let name = "hitofude-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("invalid JSON".utf8), forKey: "hitofude.session.v1")
        let game = GameModel(defaults: defaults)
        await game.startInitialGame()
        XCTAssertEqual(game.mode, .easy)
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
            XCTAssertEqual(fallback.mode, .easy)
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
        XCTAssertNil(finished.verdict)
        XCTAssertNil(finished.rival)
        date = date.addingTimeInterval(100)
        XCTAssertEqual(finished.elapsed(at: date), 0, accuracy: 0.001)
        for (seconds, expected) in [(9.0, "あなたの勝ち！"), (11.0, "相手の勝ち。もう一度挑戦しよう！")] {
            await finished.load(challenge.mode, seed: challenge.seed, rival: challenge)
            let fresh = try XCTUnwrap(finished.puzzle)
            finished.step(fresh.path[0])
            date = date.addingTimeInterval(seconds)
            for cell in fresh.path.dropFirst() { finished.step(cell) }
            XCTAssertEqual(finished.verdict, expected)
        }
    }


    func testMonthlyGoalDeduplicatesBoardsAndKeepsRewardNextMonth() throws {
        let calendar = PlayProgress.calendar(timeZone: TimeZone(secondsFromGMT: 9 * 3600)!)
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))!
        let november = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        var progress = PlayProgress()
        XCTAssertFalse(progress.record(mode: .tutorial, seed: 1, at: october, calendar: calendar))
        for seed in UInt32(1)...UInt32(9) {
            XCTAssertTrue(progress.record(mode: .easy, seed: seed, at: october, calendar: calendar))
        }
        XCTAssertEqual(progress.count(in: october, calendar: calendar), 9)
        XCTAssertFalse(progress.nightUnlocked)
        XCTAssertFalse(progress.record(mode: .easy, seed: 1, at: october, calendar: calendar))
        XCTAssertEqual(progress.count(in: october, calendar: calendar), 9)
        XCTAssertTrue(progress.record(mode: .easy, seed: 10, at: october, calendar: calendar))
        XCTAssertTrue(progress.nightUnlocked)
        XCTAssertEqual(progress.count(on: october, calendar: calendar), 10)
        XCTAssertEqual(progress.count(in: november, calendar: calendar), 0)
        XCTAssertFalse(progress.record(mode: .easy, seed: 10, at: november, calendar: calendar))
        XCTAssertTrue(progress.nightUnlocked)
        XCTAssertTrue(progress.record(mode: .easy, seed: 11, at: november, calendar: calendar))
        XCTAssertEqual(progress.count(in: november, calendar: calendar), 1)
        let restored = try JSONDecoder().decode(PlayProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertTrue(restored.nightUnlocked)
        XCTAssertEqual(restored.count(in: october, calendar: calendar), 10)
        XCTAssertEqual(restored.count(in: november, calendar: calendar), 1)
    }

    func testDailyCalendarUsesLocalDateAndDeduplicatesMediumBoard() {
        let calendar = PlayProgress.calendar(timeZone: TimeZone(secondsFromGMT: 9 * 3600)!)
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        XCTAssertEqual(PlayProgress.dayKey(today, calendar: calendar), "20261021")
        var progress = PlayProgress()
        progress.record(mode: .medium, seed: 20261021, at: today, calendar: calendar)
        XCTAssertFalse(progress.dailyCompleted(on: today, calendar: calendar))
        XCTAssertFalse(progress.record(mode: .daily, seed: 20261021, at: today, calendar: calendar))
        XCTAssertTrue(progress.dailyCompleted(on: today, calendar: calendar))
        XCTAssertEqual(progress.count(in: today, calendar: calendar), 1)
        progress.record(mode: .daily, seed: 20261021, at: tomorrow, calendar: calendar)
        XCTAssertFalse(progress.dailyCompleted(on: tomorrow, calendar: calendar))
        progress.record(mode: .daily, seed: 20261022, at: tomorrow, calendar: calendar)
        XCTAssertTrue(progress.dailyCompleted(on: tomorrow, calendar: calendar))
        XCTAssertEqual(progress.count(on: tomorrow, calendar: calendar), 1)
        // Both sides of local midnight belong to different month buckets.
        let endOfMonth = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 59))!
        let nextMonth = endOfMonth.addingTimeInterval(120)
        progress.record(mode: .hard, seed: 7, at: endOfMonth, calendar: calendar)
        progress.record(mode: .hard, seed: 8, at: nextMonth, calendar: calendar)
        XCTAssertEqual(progress.count(in: nextMonth, calendar: calendar), 1)
    }

    @MainActor
    func testCompletionProgressPersistsAndThemeRequiresUnlock() async throws {
        let name = "hitofude-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let date = Date()
        let game = GameModel(defaults: defaults, now: { date })
        game.selectNightTheme(true)
        XCTAssertFalse(game.isNightTheme)
        await game.load(.tutorial)
        for cell in Puzzle.tutorial.path { game.step(cell) }
        XCTAssertEqual(game.progress.count(in: date), 0)
        for seed in UInt32(1)...UInt32(10) {
            await game.load(.easy, seed: seed)
            let puzzle = try XCTUnwrap(game.puzzle)
            for cell in puzzle.path { game.step(cell) }
        }
        XCTAssertEqual(game.progress.count(in: date), 10)
        XCTAssertTrue(game.progress.nightUnlocked)
        game.selectNightTheme(true)
        XCTAssertTrue(game.isNightTheme)
        let restored = GameModel(defaults: defaults, now: { date })
        await restored.startInitialGame()
        XCTAssertTrue(restored.isNightTheme)
        XCTAssertEqual(restored.progress.count(in: date), 10)
        await restored.load(.easy, seed: 10)
        restored.reset()
        let puzzle = try XCTUnwrap(restored.puzzle)
        for cell in puzzle.path { restored.step(cell) }
        XCTAssertEqual(restored.progress.count(in: date), 10)
        restored.selectNightTheme(false)
        XCTAssertFalse(restored.isNightTheme)
        let standard = GameModel(defaults: defaults)
        XCTAssertFalse(standard.isNightTheme)
    }


    @MainActor
    func testQuickStartPreservesUnfinishedGamesButSkipsCompletedScreen() async throws {
        let name = "hitofude-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let game = GameModel(defaults: defaults)
        await game.startInitialGame()
        XCTAssertEqual(game.mode, .easy)
        XCTAssertEqual(game.puzzle?.size, 5)
        await game.load(.hard, seed: 1000)
        let puzzle = try XCTUnwrap(game.puzzle)
        game.step(puzzle.path[0])
        let restored = GameModel(defaults: defaults)
        await restored.startInitialGame()
        XCTAssertEqual(restored.mode, .hard)
        XCTAssertEqual(restored.seed, 1000)
        XCTAssertEqual(restored.route, [puzzle.path[0]])
        for cell in puzzle.path.dropFirst() { restored.step(cell) }
        let reopened = GameModel(defaults: defaults)
        await reopened.startInitialGame()
        XCTAssertEqual(reopened.mode, .easy)
        XCTAssertFalse(reopened.isFinished)
        XCTAssertNil(reopened.startedAt)
    }

    @MainActor
    func testReturnGreetingThresholdAndForegroundVisit() async throws {
        let name = "hitofude-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var date = Date(timeIntervalSince1970: 1_000_000)
        let game = GameModel(defaults: defaults, now: { date })
        // The initial inactive callback must not overwrite the previous visit.
        game.setActive(false)
        await game.startInitialGame()
        game.setActive(true)
        XCTAssertNil(game.returnGreeting)
        let puzzle = try XCTUnwrap(game.puzzle)
        game.step(puzzle.path[0])
        game.setActive(false)
        date = date.addingTimeInterval(72 * 3600 - 1)
        game.setActive(true)
        XCTAssertNil(game.returnGreeting)
        game.setActive(false)
        date = date.addingTimeInterval(72 * 3600)
        let returning = GameModel(defaults: defaults, now: { date })
        returning.setActive(false)
        await returning.startInitialGame()
        XCTAssertEqual(returning.returnGreeting, .star)
        XCTAssertEqual(returning.route, [puzzle.path[0]])
        returning.setActive(true)
        XCTAssertEqual(defaults.integer(forKey: "hitofude.returnCount"), 1)
        returning.setActive(false)
        date = date.addingTimeInterval(72 * 3600)
        returning.setActive(false) // Background -> inactive -> active must keep the original departure.
        returning.setActive(true)
        XCTAssertEqual(returning.returnGreeting, .leaf)
        XCTAssertEqual(defaults.integer(forKey: "hitofude.returnCount"), 2)
        XCTAssertEqual(returning.route, [puzzle.path[0]])
        XCTAssertEqual(returning.elapsed(at: date), 0, accuracy: 0.001)
    }

}
