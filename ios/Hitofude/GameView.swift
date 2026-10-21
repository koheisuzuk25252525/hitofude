import SwiftUI
import UIKit

private enum Palette {
    static let background = adaptive(0xF8F3E8, 0x1B1917)
    static let foreground = adaptive(0x1F1D22, 0xF2ECE0)
    static let cell = adaptive(0xFFFDF8, 0x262320)
    static let soft = adaptive(0xEFE7D6, 0x2B2824)
    static let accent = adaptive(0xE8553A, 0xFF7A5C)
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct GameView: View {
    @StateObject private var game = GameModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsHelp = false
    @State private var showsChallenge = false
    @State private var challengeInput = ""
    @State private var challengeError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                modes
                Button { showsChallenge = true } label: {
                    Label("リンクで対戦", systemImage: "person.2")
                }.disabled(game.isLoading)
                if let rival = game.rival {
                    Text("対戦中：相手のタイム \(GameModel.timeString(TimeInterval(rival.seconds)))")
                        .font(.callout.bold()).foregroundStyle(Palette.accent)
                    Text("ヒントは3回。中断中はタイマーが止まります。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let puzzle = game.puzzle {
                    BoardView(game: game, puzzle: puzzle)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if game.isPaused {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 18).fill(.regularMaterial)
                                    Text("一時停止中").font(.title2.bold())
                                }
                            }
                        }
                    if game.isFinished { completion }
                    controls
                    if let message = game.message {
                        Text(message).font(.callout).foregroundStyle(Palette.accent)
                            .accessibilityAddTraits(.updatesFrequently)
                    } else if game.mode == .tutorial {
                        Text("1からはじめて、7 → 11 → 16の順に、すべてのマスをなぞってね")
                            .font(.callout).multilineTextAlignment(.center)
                    }
                } else if game.isLoading {
                    VStack(spacing: 16) {
                        ProgressView().tint(Palette.accent)
                        Text("問題を作っています…")
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .accessibilityElement(children: .combine)
                } else {
                    VStack(spacing: 16) {
                        Text(game.message ?? "問題を作れませんでした")
                        Button("もう一度") { Task { await game.load(game.mode, seed: game.seed, rival: game.rival) } }
                    }.frame(maxWidth: .infinity, minHeight: 300)
                }
                Text("1から指でなぞって、すべてのマスを1回ずつ通り、いちばん大きい数字で終わろう。数字は「何番目に通るか」。")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .foregroundStyle(Palette.foreground)
        .tint(Palette.accent)
        .task { await game.startInitialGame() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            game.setActive(phase == .active)
        }
        .sheet(isPresented: $showsChallenge) { challengeSheet }
        .sheet(isPresented: $showsHelp) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 24) {
                    Text("ひと筆で、ぜんぶつなごう").font(.title2.bold())
                    Text("1のマスから、上下左右になぞります。ななめには進めません。")
                    Text("数字のあるマスは、その順番に通りましょう。すべてのマスを1回ずつ通ればクリア！")
                    Text("ひとつ前のマスへ戻ると、1手取り消せます。マスを順にタップしても遊べます。")
                    Button("れんしゅうする") {
                        showsHelp = false
                        Task { await game.load(.tutorial) }
                    }.buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding(24)
                .navigationTitle("あそびかた")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showsHelp = false } } }
            }.presentationDetents([.medium, .large])
        }
    }

    private var challengeSheet: some View {
        NavigationStack {
            Form {
                Section("相手の挑戦リンク") {
                    TextField("https://…/hitofude/#c-…", text: $challengeInput, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: challengeInput) { _, _ in challengeError = nil }
                    PasteButton(payloadType: String.self) { texts in
                        challengeInput = texts.first ?? ""
                        challengeError = nil
                    }
                }
                Section {
                    if let challenge = Challenge.parse(challengeInput) {
                        Text("\(challenge.mode.title)・相手 \(GameModel.timeString(TimeInterval(challenge.seconds)))")
                    }
                    Button("この問題で対戦する") {
                        guard let challenge = Challenge.parse(challengeInput) else {
                            challengeError = "ヒトフデの挑戦リンクを貼り付けてね"
                            return
                        }
                        showsChallenge = false
                        Task { await game.load(challenge.mode, seed: challenge.seed, rival: challenge) }
                    }
                    if let challengeError { Text(challengeError).foregroundStyle(.red) }
                } footer: {
                    Text("今の問題は対戦問題に切り替わります。リンクをタップするとWeb版が開くので、アプリではここに貼り付けてください。タイムは自己申告の気軽な対戦です。")
                }
            }
            .navigationTitle("リンクで対戦")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { showsChallenge = false } }
            }
        }.presentationDetents([.medium, .large])
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                (Text("ヒト") + Text("フデ").foregroundColor(Palette.accent))
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                Spacer()
                Button { showsHelp = true } label: {
                    Image(systemName: "questionmark.circle").font(.title2).frame(width: 44, height: 44)
                }.accessibilityLabel("あそびかた")
            }
            HStack {
                Text(game.mode.title).font(.headline)
                Spacer()
                Text("\(game.route.count)/\((game.puzzle?.size ?? game.mode.size) * (game.puzzle?.size ?? game.mode.size))")
                    .monospacedDigit().accessibilityLabel("\(game.route.count)マス通過")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(GameModel.timeString(game.elapsed(at: context.date)))
                        .monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityLabel("経過時間 \(GameModel.timeString(game.elapsed(at: context.date)))")
                }
            }
            if game.mode == .daily, game.seed != GameMode.dailySeed(), game.puzzle != nil {
                Text("保存した日の問題（\(String(game.seed))）").font(.caption).foregroundStyle(.secondary)
            }
            if let best = game.best {
                Text("ベスト \(GameModel.timeString(best))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var modes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GameMode.allCases.filter { $0 != .tutorial }) { mode in
                    Button { Task { await game.load(mode) } } label: {
                        Text(mode.title).font(.subheadline.bold())
                            .padding(.horizontal, 18).frame(minHeight: 44)
                            .background(game.mode == mode ? Palette.accent : Palette.soft, in: Capsule())
                            .foregroundStyle(game.mode == mode ? Palette.background : Palette.foreground)
                    }
                    .accessibilityAddTraits(game.mode == mode ? .isSelected : [])
                    .disabled(game.isLoading)
                }
            }
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack { hintButton; undoButton; resetButton }
            VStack { HStack { hintButton; undoButton }; resetButton }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
    private var hintButton: some View {
        Button("ヒント \(game.hintsLeft)") { game.hint() }
            .disabled(game.hintsLeft == 0 || game.isFinished || game.mode == .tutorial)
    }
    private var undoButton: some View {
        Button("ひとつ戻す") { game.undo() }.disabled(game.route.isEmpty || game.isFinished)
    }
    private var resetButton: some View {
        Button("やり直す") { game.reset() }
    }
    private var completion: some View {
        VStack(spacing: 14) {
            Text("クリア！").font(.largeTitle.bold()).foregroundStyle(Palette.accent)
            Text("\(game.mode.title)  \(GameModel.timeString(game.elapsed(at: Date())))")
            if let verdict = game.verdict {
                Text(verdict).font(.headline)
                Button("同じ問題で再挑戦") {
                    Task { await game.load(game.mode, seed: game.seed, rival: game.rival) }
                }.buttonStyle(.bordered)
            }
            if let challenge = game.challenge {
                ShareLink(item: challenge.url,
                          subject: Text("ヒトフデで対戦しよう"),
                          message: Text("\(game.mode.title)・\(GameModel.timeString(TimeInterval(challenge.seconds)))・ヒント使用\(3 - game.hintsLeft)回。このタイムに挑戦！アプリの「リンクで対戦」にリンクを貼り付けてね。")) {
                    Label("挑戦リンクを送る", systemImage: "person.2.wave.2")
                }.buttonStyle(.borderedProminent)
            }
            HStack {
                ShareLink(item: game.shareText) { Label("結果を共有", systemImage: "square.and.arrow.up") }
                Button(game.mode == .tutorial ? "きょうの1問へ" : "つぎの問題") {
                    Task { await game.load(game.mode == .tutorial ? .daily : game.mode) }
                }
            }.buttonStyle(.bordered)
        }
        .padding(20).frame(maxWidth: .infinity)
        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }
}

private struct BoardView: View {
    @ObservedObject var game: GameModel
    let puzzle: Puzzle
    @State private var previousPoint: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let step = width / CGFloat(puzzle.size)
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Palette.cell)
                ForEach(0..<(puzzle.size * puzzle.size), id: \.self) { index in
                    let cell = Cell(row: index / puzzle.size, column: index % puzzle.size)
                    let order = game.route.firstIndex(of: cell).map { $0 + 1 }
                    let clue = puzzle.clues[cell]
                    Button { game.step(cell) } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(game.highlighted == cell ? Palette.accent.opacity(0.35) :
                                      order != nil ? Palette.accent.opacity(0.16) : Palette.soft.opacity(0.5))
                            if let number = clue ?? order {
                                Text("\(number)")
                                    .font(.system(size: max(14, step * 0.38), weight: clue != nil ? .bold : .regular, design: .rounded))
                                    .foregroundStyle(Palette.foreground)
                            }
                        }
                        .frame(width: max(1, step - 6), height: max(1, step - 6))
                    }
                    .buttonStyle(.plain)
                    .position(center(of: cell, step: step))
                    .accessibilityLabel("\(cell.row + 1)行\(cell.column + 1)列、" + (clue.map { "数字\($0)" } ?? "空白") + (order.map { "、\($0)番目に通過" } ?? ""))
                }
                Path { path in
                    for (index, cell) in game.route.enumerated() {
                        let point = center(of: cell, step: step)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(Palette.accent.opacity(0.5), style: StrokeStyle(lineWidth: max(4, step * 0.13), lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .padding(0)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.foreground, lineWidth: 2).allowsHitTesting(false))
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Sample the segment so fast drags still visit intermediate cells.
                    let from = previousPoint ?? value.startLocation
                    let to = value.location
                    let distance = hypot(to.x - from.x, to.y - from.y)
                    let samples = max(1, Int(distance / max(1, step / 4)) + 1)
                    for index in 0...samples {
                        let t = CGFloat(index) / CGFloat(samples)
                        let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
                        if point.x >= 0, point.y >= 0, point.x < width, point.y < width {
                            game.step(Cell(row: Int(point.y / step), column: Int(point.x / step)))
                        }
                    }
                    previousPoint = to
                }
                .onEnded { _ in previousPoint = nil })
            .onChange(of: game.isPaused) { _, _ in previousPoint = nil }
        }
    }

    private func center(of cell: Cell, step: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(cell.column) + 0.5) * step, y: (CGFloat(cell.row) + 0.5) * step)
    }
}

#Preview { GameView() }
