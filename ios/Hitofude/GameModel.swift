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
    private var requestID = UUID()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func startInitialGame() async {
        guard puzzle == nil, !isLoading else { return }
        await load(defaults.bool(forKey: "hitofude.tutorialCompleted") ? .daily : .tutorial)
    }

    func load(_ selected: GameMode, seed explicitSeed: UInt32? = nil) async {
        let id = UUID()
        requestID = id
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
        } catch {
            guard id == requestID else { return }
            isLoading = false
            message = error.localizedDescription
        }
    }

    func reset() {
        route = []; isFinished = false; hintsLeft = 3; highlighted = nil
        message = nil; startedAt = nil; finishedAt = nil
    }

    func step(_ cell: Cell) {
        guard let puzzle, !isLoading, !isFinished,
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
        if startedAt == nil { startedAt = Date() }
        route.append(cell); highlighted = nil; message = nil
        UISelectionFeedbackGenerator().selectionChanged()
        if route.count == puzzle.size * puzzle.size { finish() }
    }

    func undo() {
        guard !isFinished, !route.isEmpty else { return }
        route.removeLast(); highlighted = nil; message = nil
    }

    func hint() {
        guard let puzzle, hintsLeft > 0, !isFinished, mode != .tutorial else { return }
        var correct = 0
        while correct < route.count, route[correct] == puzzle.path[correct] { correct += 1 }
        route = Array(route.prefix(correct))
        guard correct < puzzle.path.count else { return }
        highlighted = puzzle.path[correct]
        hintsLeft -= 1
        if startedAt == nil { startedAt = Date() }
        message = "色のついたマスへ進んでみよう"
    }

    func elapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (finishedAt ?? date).timeIntervalSince(startedAt))
    }

    static func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var shareText: String {
        "ヒトフデ \(mode.title) \(puzzle?.size ?? 0)×\(puzzle?.size ?? 0) \(Self.timeString(elapsed(at: Date())))\nseed: \(seed)"
    }

    private func finish() {
        isFinished = true; finishedAt = Date()
        let seconds = elapsed(at: Date())
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
