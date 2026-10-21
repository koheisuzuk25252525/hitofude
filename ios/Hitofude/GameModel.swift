import Foundation
import SwiftUI
import UIKit

@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var mode: GameMode = .tutorial
    @Published private(set) var puzzle: Puzzle?
    @Published private(set) var route: [Cell] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isFinished = false
    @Published private(set) var hintsLeft = 3
    @Published private(set) var highlighted: Cell?
    @Published private(set) var message: String?
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?
    @Published private(set) var seed: UInt32 = 0
    @Published private(set) var best: TimeInterval?
    @Published private(set) var isPaused = false
    @Published private(set) var rival: Challenge?
    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private let now: () -> Date
    private var requestID = UUID()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func startInitialGame() async {
        guard puzzle == nil, !isLoading else { return }
        if restoreSession() { return }
        await load(defaults.bool(forKey: "hitofude.tutorialCompleted") ? .daily : .tutorial)
    }

    func load(_ selected: GameMode, seed explicitSeed: UInt32? = nil, rival opponent: Challenge? = nil) async {
        let id = UUID()
        requestID = id
        rival = opponent
        mode = selected
        seed = explicitSeed ?? (selected == .daily ? GameMode.dailySeed() : UInt32.random(in: .min ... .max))
        let selectedSeed = seed
        puzzle = nil
        reset()
        isLoading = true
        best = defaults.object(forKey: "hitofude.best.\(selected.rawValue)") as? Double
        do {
            let generated = try await Task.detached(priority: .userInitiated) {
                try PuzzleGenerator.generate(mode: selected, seed: selectedSeed)
            }.value
            guard id == requestID else { return }
            puzzle = generated
            isLoading = false
            saveSession()
        } catch {
            guard id == requestID else { return }
            isLoading = false
            message = error.localizedDescription
        }
    }

    func reset() {
        route = []; isFinished = false; hintsLeft = 3; highlighted = nil
        message = nil; startedAt = nil; finishedAt = nil
        accumulated = 0; segmentStart = nil
        saveSession()
    }

    func step(_ cell: Cell) {
        guard let puzzle, !isLoading, !isFinished, !isPaused,
              (0..<puzzle.size).contains(cell.row), (0..<puzzle.size).contains(cell.column) else { return }
        if route.last == cell { return }
        if route.count > 1, route[route.count - 2] == cell { undo(); return }
        if let last = route.last {
            guard last.isAdjacent(to: cell), !route.contains(cell) else { return }
        } else {
            guard puzzle.clues[cell] == 1 else { message = "1のマスからはじめてね"; return }
        }
        if let clue = puzzle.clues[cell], clue != route.count + 1 {
            message = "そのマスは\(clue)番目に通ってね"
            return
        }
        beginClock()
        route.append(cell); highlighted = nil; message = nil
        UISelectionFeedbackGenerator().selectionChanged()
        if route.count == puzzle.size * puzzle.size { finish() }
        saveSession()
    }

    func undo() {
        guard !isFinished, !isPaused, !route.isEmpty else { return }
        route.removeLast(); highlighted = nil; message = nil
        saveSession()
    }

    func hint() {
        guard let puzzle, hintsLeft > 0, !isFinished, !isPaused, mode != .tutorial else { return }
        var correct = 0
        while correct < route.count, route[correct] == puzzle.path[correct] { correct += 1 }
        route = Array(route.prefix(correct))
        guard correct < puzzle.path.count else { return }
        highlighted = puzzle.path[correct]
        hintsLeft -= 1
        beginClock()
        message = "色のついたマスへ進んでみよう"
        saveSession()
    }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (segmentStart.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    static func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var shareText: String {
        "ヒトフデ \(mode.title) \(puzzle?.size ?? 0)×\(puzzle?.size ?? 0) \(Self.timeString(elapsed(at: Date())))\nseed: \(seed)"
    }

    private func beginClock() {
        if startedAt == nil { startedAt = now() }
        if segmentStart == nil, !isPaused, !isFinished { segmentStart = now() }
    }

    func setActive(_ active: Bool) {
        if !active {
            accumulated = elapsed(at: now())
            segmentStart = nil
            isPaused = true
        } else {
            isPaused = false
            if startedAt != nil, !isFinished, segmentStart == nil { segmentStart = now() }
        }
        saveSession()
    }

    private struct Session: Codable {
        let version: Int
        let mode: GameMode
        let seed: UInt32
        let puzzle: Puzzle
        let route: [Cell]
        let hintsLeft: Int
        let highlighted: Cell?
        let elapsed: TimeInterval
        let hasStarted: Bool
        let isFinished: Bool
        let rival: Challenge?

        var isValid: Bool {
            let count = mode.size * mode.size
            guard version == 1, puzzle.size == mode.size,
                  puzzle.path.count == count, Set(puzzle.path).count == count,
                  puzzle.path.allSatisfy({ (0..<mode.size).contains($0.row) && (0..<mode.size).contains($0.column) }),
                  zip(puzzle.path, puzzle.path.dropFirst()).allSatisfy({ $0.0.isAdjacent(to: $0.1) }),
                  puzzle.clues[puzzle.path[0]] == 1, puzzle.clues[puzzle.path[count - 1]] == count,
                  puzzle.clues.allSatisfy({ cell, value in
                      (1...count).contains(value) && puzzle.path[value - 1] == cell
                  }),
                  route.count <= count, Set(route).count == route.count,
                  route.allSatisfy({ puzzle.path.contains($0) }),
                  zip(route, route.dropFirst()).allSatisfy({ $0.0.isAdjacent(to: $0.1) }),
                  route.isEmpty || puzzle.clues[route[0]] == 1,
                  route.enumerated().allSatisfy({ index, cell in
                      puzzle.clues[cell] == nil || puzzle.clues[cell] == index + 1
                  }),
                  (0...3).contains(hintsLeft), elapsed.isFinite, (0...31_536_000).contains(elapsed),
                  isFinished == (route.count == count),
                  hasStarted || (route.isEmpty && elapsed == 0 && hintsLeft == 3),
                  highlighted == nil || (puzzle.path.contains(highlighted!) && !isFinished),
                  rival == nil || (rival!.isValid && rival!.mode == mode && rival!.seed == seed)
            else { return false }
            return true
        }
    }

    private func saveSession() {
        guard let puzzle, !isLoading else { return }
        let session = Session(version: 1, mode: mode, seed: seed, puzzle: puzzle,
                              route: route, hintsLeft: hintsLeft, highlighted: highlighted,
                              elapsed: elapsed(at: now()), hasStarted: startedAt != nil,
                              isFinished: isFinished, rival: rival)
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: "hitofude.session.v1")
    }

    private func restoreSession() -> Bool {
        guard let data = defaults.data(forKey: "hitofude.session.v1") else { return false }
        guard data.count <= 65_536,
              let session = try? JSONDecoder().decode(Session.self, from: data), session.isValid else {
            defaults.removeObject(forKey: "hitofude.session.v1")
            return false
        }
        mode = session.mode; seed = session.seed; puzzle = session.puzzle
        route = session.route; hintsLeft = session.hintsLeft; highlighted = session.highlighted
        rival = session.rival; isFinished = session.isFinished; accumulated = session.elapsed
        startedAt = session.hasStarted ? now() : nil
        finishedAt = session.isFinished ? now() : nil
        segmentStart = session.hasStarted && !isFinished && !isPaused ? now() : nil
        best = defaults.object(forKey: "hitofude.best.\(mode.rawValue)") as? Double
        message = "前のつづきから再開しました"
        return true
    }

    var challenge: Challenge? {
        guard isFinished, mode != .tutorial else { return nil }
        let seconds = Int(elapsed(at: now()).rounded())
        let result = Challenge(mode: mode, seed: seed, seconds: seconds)
        return result.isValid ? result : nil
    }

    var verdict: String? {
        guard isFinished, let rival else { return nil }
        let seconds = Int(elapsed(at: now()).rounded())
        if seconds < rival.seconds { return "あなたの勝ち！" }
        if seconds == rival.seconds { return "引き分け！" }
        return "相手の勝ち。もう一度挑戦しよう！"
    }

    private func finish() {
        accumulated = elapsed(at: now()); segmentStart = nil
        isFinished = true; finishedAt = now()
        let seconds = accumulated
        if mode == .tutorial {
            defaults.set(true, forKey: "hitofude.tutorialCompleted")
        } else if best == nil || seconds < best! {
            best = seconds
            defaults.set(seconds, forKey: "hitofude.best.\(mode.rawValue)")
        }
        if mode == .daily { defaults.set(seconds, forKey: "hitofude.daily.\(seed)") }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
