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
    @Published private(set) var progress: PlayProgress
    @Published private(set) var isNightTheme: Bool
    @Published private(set) var completionMessage: String?
    @Published private(set) var returnGreeting: ReturnGreeting?
    private var attemptID = UUID().uuidString
    private var pauseReason = "background"
    private let analytics: PlayEventRecording?
    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private let now: () -> Date
    private var requestID = UUID()
    private let defaults: UserDefaults
    private let generate: @Sendable (GameMode, UInt32) throws -> Puzzle

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         analytics: PlayEventRecording? = nil,
         generate: @escaping @Sendable (GameMode, UInt32) throws -> Puzzle = { try PuzzleGenerator.generate(mode: $0, seed: $1) }) {
        self.analytics = analytics
        self.defaults = defaults
        self.now = now
        self.generate = generate
        let savedProgress: PlayProgress
        if let data = defaults.data(forKey: "hitofude.progress.v1"),
           let saved = try? JSONDecoder().decode(PlayProgress.self, from: data) {
            savedProgress = saved
        } else { savedProgress = PlayProgress() }
        progress = savedProgress
        isNightTheme = savedProgress.nightUnlocked && defaults.bool(forKey: "hitofude.nightTheme")
    }

    func selectNightTheme(_ selected: Bool) {
        guard !selected || progress.nightUnlocked else { return }
        isNightTheme = selected
        defaults.set(selected, forKey: "hitofude.nightTheme")
    }

    func startInitialGame() async {
        guard puzzle == nil, !isLoading else { return }
        registerVisit()
        if restoreSession(), !isFinished { return }
        await load(.easy)
    }

    func load(_ selected: GameMode, seed explicitSeed: UInt32? = nil, rival opponent: Challenge? = nil) async {
        if puzzle != nil, !isFinished { record(.leave, reason: "another_puzzle") }
        let id = UUID()
        requestID = id
        rival = opponent
        mode = selected
        seed = explicitSeed ?? (selected == .daily ? GameMode.dailySeed(date: now()) : UInt32.random(in: .min ... .max))
        let selectedSeed = seed
        puzzle = nil
        reset()
        isLoading = true
        best = defaults.object(forKey: "hitofude.best.\(selected.rawValue)") as? Double
        let generate = self.generate
        do {
            let generated = try await Task.detached(priority: .userInitiated) {
                try generate(selected, selectedSeed)
            }.value
            guard id == requestID else { return }
            puzzle = generated
            isLoading = false
            record(.ready)
            saveSession()
        } catch {
            guard id == requestID else { return }
            isLoading = false
            message = error.localizedDescription
            record(.generationFailed)
        }
    }

    func reset() {
        if puzzle != nil, startedAt != nil, !isFinished { record(.restart) }
        attemptID = UUID().uuidString
        route = []; isFinished = false; hintsLeft = 3; highlighted = nil
        message = nil; startedAt = nil; finishedAt = nil
        accumulated = 0; segmentStart = nil
        completionMessage = nil
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
        guard let puzzle, hintsLeft > 0, highlighted == nil, !isFinished, !isPaused, mode != .tutorial else { return }
        var correct = 0
        while correct < route.count, route[correct] == puzzle.path[correct] { correct += 1 }
        let corrected = correct < route.count
        route = Array(route.prefix(correct))
        guard correct < puzzle.path.count else { return }
        highlighted = puzzle.path[correct]
        beginClock()
        hintsLeft -= 1
        record(.hint)
        message = (corrected ? "\(correct)マス目まで戻しました。" : "") + "\(correct + 1)番目は、目印のマスです"
        saveSession()
    }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (segmentStart.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    var finalTime: TimeInterval? { isFinished ? accumulated : nil }

    var nextClue: Int? {
        guard let puzzle, !isFinished else { return nil }
        return puzzle.clues.values.filter { $0 > route.count }.min()
    }

    var guidance: String {
        if isFinished { return "すべてのマスが、一本の線に。" }
        guard !route.isEmpty, let nextClue else { return "「1」からなぞってスタート" }
        return "次の数字 \(nextClue) まで、あと \(nextClue - route.count) マス"
    }

    static func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var shareText: String {
        let summary = "ヒトフデ \(mode.title) \(puzzle?.size ?? 0)×\(puzzle?.size ?? 0) \(Self.timeString(finalTime ?? elapsed(at: now())))\nヒント \(3 - hintsLeft)回\nseed: \(seed)"
        guard let rival, let finalTime else { return summary }
        let seconds = Int(finalTime.rounded())
        return summary + "\nリンクを送った人：\(Self.timeString(TimeInterval(rival.seconds)))\n挑戦した人：\(Self.timeString(TimeInterval(seconds)))\nタイム差：\(abs(seconds - rival.seconds))秒\n\(verdict ?? "")"
    }

    private func record(_ event: PlayEvent, reason: String? = nil) {
        let total = (puzzle?.size ?? mode.size) * (puzzle?.size ?? mode.size)
        var parameters: [String: Any] = [
            "attempt_id": attemptID, "mode": mode.rawValue,
            "is_challenge": rival == nil ? 0 : 1,
            "progress_bucket": min(10, route.count * 10 / total) * 10,
            "elapsed_seconds": Int(min(31_536_000, max(0, elapsed(at: now())))),
            "hints_used": 3 - hintsLeft, "started": startedAt == nil ? 0 : 1, "completed": isFinished ? 1 : 0
        ]
        if let reason { parameters["reason"] = reason }
        analytics?.record(event, parameters: parameters)
    }

    var feedbackContext: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "ヒトフデ \(version)（\(build)）\n\(UIDevice.current.model) / iOS \(UIDevice.current.systemVersion)\n難易度：\(mode.title) / seed：\(seed)\n進捗：\(route.count)/\(mode.size * mode.size)、ヒント残り：\(hintsLeft)"
    }

    private func beginClock() {
        if startedAt == nil { startedAt = now(); record(.start) }
        if segmentStart == nil, !isPaused, !isFinished { segmentStart = now() }
    }

    func setActive(_ active: Bool, reason: String = "background") {
        let wasActive = !isPaused
        if !active {
            if wasActive || pauseReason != reason { pauseReason = reason; if puzzle != nil { record(.pause, reason: reason) } }
            accumulated = elapsed(at: now())
            segmentStart = nil
            isPaused = true
        } else {
            if !wasActive, puzzle != nil { record(.resume, reason: pauseReason) }
            registerVisit()
            isPaused = false
            if startedAt != nil, !isFinished, segmentStart == nil { segmentStart = now() }
        }
        if !active, wasActive, puzzle != nil { defaults.set(now(), forKey: "hitofude.lastVisit") }
        saveSession()
    }

    private func registerVisit() {
        let date = now()
        if let previous = defaults.object(forKey: "hitofude.lastVisit") as? Date,
           date.timeIntervalSince(previous) >= 72 * 3600 {
            let count = defaults.integer(forKey: "hitofude.returnCount")
            returnGreeting = ReturnGreeting.allCases[max(0, count) % ReturnGreeting.allCases.count]
            defaults.set((max(0, count) % ReturnGreeting.allCases.count) + 1, forKey: "hitofude.returnCount")
        }
        defaults.set(date, forKey: "hitofude.lastVisit")
    }

    private struct Session: Codable {
        let attemptID: String?
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
        let session = Session(attemptID: attemptID, version: 1, mode: mode, seed: seed, puzzle: puzzle,
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
        attemptID = session.attemptID.flatMap { UUID(uuidString: $0) }?.uuidString ?? UUID().uuidString
        mode = session.mode; seed = session.seed; puzzle = session.puzzle
        route = session.route; hintsLeft = session.hintsLeft; highlighted = session.highlighted
        rival = session.rival; isFinished = session.isFinished; accumulated = session.elapsed
        startedAt = session.hasStarted ? now() : nil
        finishedAt = session.isFinished ? now() : nil
        segmentStart = session.hasStarted && !isFinished && !isPaused ? now() : nil
        best = defaults.object(forKey: "hitofude.best.\(mode.rawValue)") as? Double
        if !isFinished { record(.restored) }
        message = highlighted == nil ? "前のつづきから再開しました" : "前のつづきです。\(route.count + 1)番目は、目印のマスです"
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
        record(.complete)
        let seconds = accumulated
        let improved = best.map { seconds < $0 } ?? false
        if mode == .tutorial {
            defaults.set(true, forKey: "hitofude.tutorialCompleted")
        } else if best == nil || seconds < best! {
            best = seconds
            defaults.set(seconds, forKey: "hitofude.best.\(mode.rawValue)")
        }
        if mode == .daily { defaults.set(seconds, forKey: "hitofude.daily.\(seed)") }
        let wasUnlocked = progress.nightUnlocked
        progress.record(mode: mode, seed: seed, at: now())
        if let data = try? JSONEncoder().encode(progress) {
            defaults.set(data, forKey: "hitofude.progress.v1")
        }
        if !wasUnlocked && progress.nightUnlocked {
            completionMessage = "今月10問達成！「夜空」の色が使えるようになったよ"
        } else if mode == .tutorial {
            completionMessage = "準備できました。さくっと一問へ。"
        } else if improved {
            completionMessage = "自己ベストを更新！"
        } else {
            completionMessage = hintsLeft == 3 ? "ヒントなしで、つながりました。" : "考えた道が、一本につながりました。"
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
