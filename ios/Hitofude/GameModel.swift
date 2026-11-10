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
    @Published private(set) var superHintUnlocked = false
    private var pendingSuperHint: (token: UUID, attempt: String)?
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
    private let sounds: GameSoundPlaying?
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private var isTracingSample = false
    private var sampleNeedsSave = false
    private var sampleSound: GameSound?
    private var sampleSelectionChanged = false
    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private let now: () -> Date
    private var requestID = UUID()
    private let defaults: UserDefaults
    private var preparedNext: [GameMode: (seed: UInt32, puzzle: Puzzle)] = [:]
    private(set) var preparationTask: Task<Void, Never>?
    private let prepare: @Sendable (GameMode, Int) throws -> (seed: UInt32, puzzle: Puzzle)
    private let prefetch: @Sendable (GameMode, UInt32) throws -> Puzzle
    private let generate: @Sendable (GameMode, UInt32) throws -> Puzzle

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         analytics: PlayEventRecording? = nil, sounds: GameSoundPlaying? = nil,
         prepare: @escaping @Sendable (GameMode, Int) throws -> (seed: UInt32, puzzle: Puzzle) = { try PuzzleGenerator.prepared(mode: $0, index: $1) },
         prefetch: @escaping @Sendable (GameMode, UInt32) throws -> Puzzle = { try PuzzleGenerator.generate(mode: $0, seed: $1, timeoutMilliseconds: 1500) },
         generate: @escaping @Sendable (GameMode, UInt32) throws -> Puzzle = { try PuzzleGenerator.generate(mode: $0, seed: $1) }) {
        self.analytics = analytics
        self.sounds = sounds
        self.defaults = defaults
        self.now = now
        self.generate = generate
        self.prepare = prepare
        self.prefetch = prefetch
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
        let usesPrepared = explicitSeed == nil && opponent == nil && selected != .daily && selected != .tutorial
        let next = usesPrepared ? preparedNext.removeValue(forKey: selected) : nil
        let cursorKey = "hitofude.prepared.\(selected.rawValue)"
        let cursor = defaults.object(forKey: cursorKey) == nil ? Int.random(in: 0..<16) : defaults.integer(forKey: cursorKey)
        puzzle = nil
        hintsLeft = 3
        superHintUnlocked = false
        reset()
        isLoading = true
        best = defaults.object(forKey: "hitofude.best.\(selected.rawValue)") as? Double
        let generate = self.generate
        let prepare = self.prepare
        do {
            let generated = try await Task.detached(priority: .userInitiated) { () throws -> (seed: UInt32, puzzle: Puzzle) in
                if let next { return next }
                if usesPrepared { return try prepare(selected, cursor) }
                return (selectedSeed, try generate(selected, selectedSeed))
            }.value
            guard id == requestID else { return }
            seed = generated.seed
            puzzle = generated.puzzle
            if usesPrepared && next == nil { defaults.set((cursor % 16 + 1) % 16, forKey: cursorKey) }
            isLoading = false
            record(.ready)
            saveSession()
            if usesPrepared { prepareNextPuzzle(selected) }
        } catch {
            guard id == requestID else { return }
            isLoading = false
            message = error.localizedDescription
            record(.generationFailed)
        }
    }

    // At most one bounded, low-priority generation runs at a time. A timeout is
    // invisible to the player: the next request can always use the offline bank.
    private func prepareNextPuzzle(_ selected: GameMode) {
        guard preparationTask == nil, preparedNext[selected] == nil else { return }
        let prefetch = self.prefetch
        let nextSeed = UInt32.random(in: .min ... .max)
        preparationTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                try? prefetch(selected, nextSeed)
            }.value
            guard let self else { return }
            if let result { self.preparedNext[selected] = (nextSeed, result) }
            self.preparationTask = nil
        }
    }

    func reset() {
        sounds?.stop()
        if puzzle != nil, startedAt != nil, !isFinished { record(.restart) }
        attemptID = UUID().uuidString
        route = []; isFinished = false; highlighted = nil
        pendingSuperHint = nil
        message = nil; startedAt = nil; finishedAt = nil
        accumulated = 0; segmentStart = nil
        completionMessage = nil
        saveSession()
    }

    /// Preserve every crossed cell, but encode/store only the final state of one input sample.
    func trace(_ cells: [Cell]) {
        guard !cells.isEmpty else { return }
        isTracingSample = true
        sampleSound = nil
        sampleSelectionChanged = false
        defer {
            isTracingSample = false
            if sampleSelectionChanged && !isFinished { selectionFeedback.selectionChanged() }
            if let sampleSound { sounds?.play(sampleSound) }
            sampleSound = nil
            if sampleNeedsSave { sampleNeedsSave = false; saveSession() }
        }
        for cell in cells { step(cell) }
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
        let keepsOpeningHint = route.isEmpty && highlighted == puzzle.path[1]
        route.append(cell)
        if keepsOpeningHint { message = hintGuidance }
        else { highlighted = nil; message = nil }
        let note = GameSound.step(index: route.count - 1, total: puzzle.size * puzzle.size)
        if isTracingSample { sampleSelectionChanged = true; sampleSound = note }
        else { selectionFeedback.selectionChanged(); sounds?.play(note) }
        if route.count == puzzle.size * puzzle.size { finish() }
        saveSession()
    }

    func undo() {
        guard !isFinished, !isPaused, !route.isEmpty else { return }
        route.removeLast(); highlighted = nil; message = nil
        if isTracingSample { sampleSound = nil; sampleSelectionChanged = false }
        saveSession()
    }

    func hint() {
        guard let puzzle, hintsLeft > 0, highlighted == nil, !isFinished, !isPaused, mode != .tutorial else { return }
        var correct = 0
        while correct < route.count, route[correct] == puzzle.path[correct] { correct += 1 }
        let corrected = correct < route.count
        route = Array(route.prefix(correct))
        guard correct < puzzle.path.count else { return }
        let hintIndex = max(1, correct)
        highlighted = puzzle.path[hintIndex]
        beginClock()
        hintsLeft -= 1
        record(.hint)
        message = (corrected ? "\(correct)マス目まで戻しました。" : "") + hintGuidance
        saveSession()
    }

    var canRequestSuperHint: Bool {
        puzzle != nil && !isLoading && !isFinished && hintsLeft == 0 &&
            !superHintUnlocked && mode != .tutorial
    }

    /// A reward belongs to this attempt only; late/repeated ad callbacks cannot unlock another game.
    func beginSuperHintReward() -> UUID? {
        guard canRequestSuperHint, pendingSuperHint == nil else { return nil }
        let token = UUID()
        pendingSuperHint = (token, attemptID)
        return token
    }

    func cancelSuperHintReward(_ token: UUID) {
        if pendingSuperHint?.token == token { pendingSuperHint = nil }
    }

    @discardableResult
    func earnSuperHint(_ token: UUID) -> Bool {
        guard let pending = pendingSuperHint, pending.token == token,
              pending.attempt == attemptID, canRequestSuperHint else { return false }
        pendingSuperHint = nil
        superHintUnlocked = true
        highlighted = nil
        beginClock()
        message = "スーパーヒント：数字の順になぞってみよう"
        record(.superHint)
        saveSession()
        return true
    }

    var hintNumber: Int? {
        guard let highlighted, let index = puzzle?.path.firstIndex(of: highlighted) else { return nil }
        return index + 1
    }

    private var hintGuidance: String {
        guard let hintNumber else { return "" }
        return route.isEmpty && hintNumber == 2
            ? "「1」から、目印の2マス目へ進んでね"
            : "\(hintNumber)番目は、目印のマスです"
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
        let summary = "ヒトフデ \(mode.title) \(puzzle?.size ?? 0)×\(puzzle?.size ?? 0) \(Self.timeString(finalTime ?? elapsed(at: now())))\nヒント \(3 - hintsLeft)回\(superHintUnlocked ? "・スーパーヒント使用" : "")\nseed: \(seed)"
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
            "hints_used": 3 - hintsLeft, "super_hint_used": superHintUnlocked ? 1 : 0, "started": startedAt == nil ? 0 : 1, "completed": isFinished ? 1 : 0
        ]
        if let reason { parameters["reason"] = reason }
        analytics?.record(event, parameters: parameters)
    }

    var feedbackContext: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "ヒトフデ \(version)（\(build)）\n\(UIDevice.current.model) / iOS \(UIDevice.current.systemVersion)\n難易度：\(mode.title) / seed：\(seed)\n進捗：\(route.count)/\(mode.size * mode.size)、ヒント残り：\(hintsLeft)、スーパーヒント：\(superHintUnlocked ? "使用" : "未使用")"
    }

    private func beginClock() {
        if startedAt == nil { startedAt = now(); record(.start) }
        if segmentStart == nil, !isPaused, !isFinished { segmentStart = now() }
    }

    func setActive(_ active: Bool, reason: String = "background") {
        let wasActive = !isPaused
        if !active {
            sounds?.stop()
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
        let superHintUnlocked: Bool?
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
                  hasStarted || (route.isEmpty && elapsed == 0),
                  superHintUnlocked != true || (hintsLeft == 0 && mode != .tutorial),
                  highlighted == nil || (puzzle.path.contains(highlighted!) && !isFinished),
                  rival == nil || (rival!.isValid && rival!.mode == mode && rival!.seed == seed)
            else { return false }
            return true
        }
    }

    private func saveSession() {
        if isTracingSample { sampleNeedsSave = true; return }
        guard let puzzle, !isLoading else { return }
        let session = Session(attemptID: attemptID, version: 1, mode: mode, seed: seed, puzzle: puzzle,
                              route: route, hintsLeft: hintsLeft, superHintUnlocked: superHintUnlocked, highlighted: highlighted,
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
        superHintUnlocked = session.superHintUnlocked ?? false
        rival = session.rival; isFinished = session.isFinished; accumulated = session.elapsed
        startedAt = session.hasStarted ? now() : nil
        finishedAt = session.isFinished ? now() : nil
        segmentStart = session.hasStarted && !isFinished && !isPaused ? now() : nil
        best = defaults.object(forKey: "hitofude.best.\(mode.rawValue)") as? Double
        if !isFinished { record(.restored) }
        message = highlighted == nil ? "前のつづきから再開しました" : "前のつづきです。" + hintGuidance
        return true
    }

    var challenge: Challenge? {
        guard isFinished, mode != .tutorial, !superHintUnlocked else { return nil }
        let seconds = Int(elapsed(at: now()).rounded())
        let result = Challenge(mode: mode, seed: seed, seconds: seconds)
        return result.isValid ? result : nil
    }

    var verdict: String? {
        guard isFinished, let rival else { return nil }
        if superHintUnlocked { return "スーパーヒント使用（タイム比較なし）" }
        let seconds = Int(elapsed(at: now()).rounded())
        if seconds < rival.seconds { return "あなたの勝ち！" }
        if seconds == rival.seconds { return "引き分け！" }
        return "相手の勝ち。もう一度挑戦しよう！"
    }

    private func finish() {
        accumulated = elapsed(at: now()); segmentStart = nil
        isFinished = true; finishedAt = now()
        record(.complete)
        if isTracingSample { sampleSound = .clear } else { sounds?.play(.clear) }
        let seconds = accumulated
        let improved = !superHintUnlocked && (best.map { seconds < $0 } ?? false)
        if mode == .tutorial {
            defaults.set(true, forKey: "hitofude.tutorialCompleted")
        } else if !superHintUnlocked && (best == nil || seconds < best!) {
            best = seconds
            defaults.set(seconds, forKey: "hitofude.best.\(mode.rawValue)")
        }
        if mode == .daily, !superHintUnlocked { defaults.set(seconds, forKey: "hitofude.daily.\(seed)") }
        let wasUnlocked = progress.nightUnlocked
        progress.record(mode: mode, seed: seed, at: now())
        if let data = try? JSONEncoder().encode(progress) {
            defaults.set(data, forKey: "hitofude.progress.v1")
        }
        if !wasUnlocked && progress.nightUnlocked {
            completionMessage = "今月10問達成！「夜空」の色が使えるようになったよ"
        } else if mode == .tutorial {
            completionMessage = "準備できました。さくっと一問へ。"
        } else if superHintUnlocked {
            completionMessage = "スーパーヒントで、つながりました。"
        } else if improved {
            completionMessage = "自己ベストを更新！"
        } else {
            completionMessage = hintsLeft == 3 ? "ヒントなしで、つながりました。" : "考えた道が、一本につながりました。"
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
