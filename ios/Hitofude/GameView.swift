import SwiftUI
import UIKit

private struct Palette {
    let isNight: Bool
    var background: Color { isNight ? Self.color(0x101B32) : Self.adaptive(0xF8F3E8, 0x1B1917) }
    var foreground: Color { isNight ? Self.color(0xF2F5FF) : Self.adaptive(0x1F1D22, 0xF2ECE0) }
    var cell: Color { isNight ? Self.color(0x182743) : Self.adaptive(0xFFFDF8, 0x262320) }
    var soft: Color { isNight ? Self.color(0x263958) : Self.adaptive(0xEFE7D6, 0x2B2824) }
    var accent: Color { isNight ? Self.color(0xF6CC78) : Self.adaptive(0xE8553A, 0xFF7A5C) }
    private static func color(_ hex: UInt32) -> Color { Color(uiColor: uiColor(hex)) }
    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(isNight: false)
}
private extension EnvironmentValues {
    var hitofudePalette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

struct GameView: View {
    @StateObject private var game = GameModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsProgress = false
    @State private var showsHelp = false
    private var palette: Palette { Palette(isNight: game.isNightTheme) }
    @State private var showsChallenge = false
    @State private var challengeInput = ""
    @State private var challengeError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if let greeting = game.returnGreeting {
                    ReturnGreetingView(greeting: greeting)
                }
                if let rival = game.rival {
                    Text("対戦中：相手のタイム \(GameModel.timeString(TimeInterval(rival.seconds)))")
                        .font(.callout.bold()).foregroundStyle(palette.accent)
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
                        Text(message).font(.callout).foregroundStyle(palette.accent)
                            .accessibilityAddTraits(.updatesFrequently)
                    } else if game.mode == .tutorial {
                        Text("1からはじめて、7 → 11 → 16の順に、すべてのマスをなぞってね")
                            .font(.callout).multilineTextAlignment(.center)
                    }
                } else if game.isLoading {
                    VStack(spacing: 16) {
                        ProgressView().tint(palette.accent)
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
                Button { Task { await game.load(.easy) } } label: {
                    Label("新しいさくっと1問", systemImage: "arrow.right")
                }.buttonStyle(.borderedProminent).disabled(game.isLoading)
                DisclosureGroup("ほかの遊び方・記録") {
                    VStack(spacing: 16) {
                        modes
                        Button { showsChallenge = true } label: {
                            Label("リンクで対戦", systemImage: "person.2")
                        }.disabled(game.isLoading)
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            progressCard(at: context.date)
                        }
                    }.padding(.top, 12)
                }
                Text("1から指でなぞって、すべてのマスを1回ずつ通り、いちばん大きい数字で終わろう。数字は「何番目に通るか」。")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background.ignoresSafeArea())
        .foregroundStyle(palette.foreground)
        .tint(palette.accent)
        .environment(\.hitofudePalette, palette)
        .preferredColorScheme(game.isNightTheme ? .dark : nil)
        .task { await game.startInitialGame() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            game.setActive(phase == .active)
        }
        .sheet(isPresented: $showsProgress) {
            ProgressCalendarView(game: game)
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

    private func progressCard(at date: Date) -> some View {
        let count = game.progress.count(in: date)
        return Button { showsProgress = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("今月のひとふで", systemImage: "calendar")
                    Spacer()
                    Text("\(count)／10問").monospacedDigit()
                }.font(.subheadline.bold())
                ProgressView(value: Double(min(count, 10)), total: 10).tint(palette.accent)
                Text(count >= 10 ? "今月の目標達成！休みながら、自分のペースで。" :
                     game.progress.nightUnlocked ? "あと\(10 - count)問で今月の目標達成。" :
                     "あと\(10 - count)問で「夜空」の色をプレゼント。")
                    .font(.caption)
            }
            .padding(16).background(palette.soft, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(palette.foreground)
        }
        .buttonStyle(.plain)
        .accessibilityHint("達成カレンダーと色の設定を開く")
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
                (Text("ヒト") + Text("フデ").foregroundColor(palette.accent))
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                Spacer()
                Button { showsHelp = true } label: {
                    Image(systemName: "questionmark.circle").font(.title2).frame(width: 44, height: 44)
                }.accessibilityLabel("あそびかた")
            }
            HStack {
                Text(game.mode == .easy ? "さくっと1問" : game.mode.title).font(.headline)
                Spacer()
                Text("\(game.route.count)/\((game.puzzle?.size ?? game.mode.size) * (game.puzzle?.size ?? game.mode.size))")
                    .monospacedDigit().accessibilityLabel("\(game.route.count)マス通過")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(GameModel.timeString(game.elapsed(at: context.date)))
                        .monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityLabel("経過時間 \(GameModel.timeString(game.elapsed(at: context.date)))")
                }
            }
            if game.mode == .easy {
                Text("1から指でなぞろう。数字は「何番目に通るか」。")
                    .font(.caption).foregroundStyle(.secondary)
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
                            .background(game.mode == mode ? palette.accent : palette.soft, in: Capsule())
                            .foregroundStyle(game.mode == mode ? palette.background : palette.foreground)
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
            Text("クリア！").font(.largeTitle.bold()).foregroundStyle(palette.accent)
            Text("\(game.mode.title)  \(GameModel.timeString(game.elapsed(at: Date())))")
            if game.hintsLeft == 3, game.mode != .tutorial {
                Text("ヒントなしで解けたね").font(.headline)
            }
            if let completionMessage = game.completionMessage {
                Text(completionMessage).multilineTextAlignment(.center)
            }
            Button("達成カレンダーを見る") { showsProgress = true }
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
                Button("もう1問だけ") {
                    Task { await game.load(.easy) }
                }
            }.buttonStyle(.bordered)
        }
        .padding(20).frame(maxWidth: .infinity)
        .background(palette.soft, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }
}

private struct ReturnGreetingView: View {
    let greeting: ReturnGreeting
    @Environment(\.hitofudePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: greeting.symbol)
                .font(.title2).foregroundStyle(palette.accent)
                .rotationEffect(.degrees(appeared ? 0 : -12))
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting.text).font(.callout.bold())
                Text("1問だけでも、ごゆっくり。").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(palette.soft, in: RoundedRectangle(cornerRadius: 14))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BoardView: View {
    @Environment(\.hitofudePalette) private var palette
    @ObservedObject var game: GameModel
    let puzzle: Puzzle
    @State private var previousPoint: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let step = width / CGFloat(puzzle.size)
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(palette.cell)
                ForEach(0..<(puzzle.size * puzzle.size), id: \.self) { index in
                    let cell = Cell(row: index / puzzle.size, column: index % puzzle.size)
                    let order = game.route.firstIndex(of: cell).map { $0 + 1 }
                    let clue = puzzle.clues[cell]
                    Button { game.step(cell) } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(game.highlighted == cell ? palette.accent.opacity(0.35) :
                                      order != nil ? palette.accent.opacity(0.16) : palette.soft.opacity(0.5))
                            if let number = clue ?? order {
                                Text("\(number)")
                                    .font(.system(size: max(14, step * 0.38), weight: clue != nil ? .bold : .regular, design: .rounded))
                                    .foregroundStyle(palette.foreground)
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
                .stroke(palette.accent.opacity(0.5), style: StrokeStyle(lineWidth: max(4, step * 0.13), lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .padding(0)
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.foreground, lineWidth: 2).allowsHitTesting(false))
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

private struct ProgressCalendarView: View {
    @ObservedObject var game: GameModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hitofudePalette) private var palette
    @State private var month = Date()
    @State private var selectedDay = Date()
    private let calendar = PlayProgress.calendar()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
    }
    private var leadingSpaces: Int { (calendar.component(.weekday, from: monthStart) + 5) % 7 }
    private var days: Int { calendar.range(of: .day, in: .month, for: monthStart)!.count }
    private var title: String {
        "\(String(calendar.component(.year, from: month)))年\(calendar.component(.month, from: month))月"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("前の月")
                        Spacer()
                        Text(title).font(.title2.bold())
                        Spacer()
                        Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .accessibilityLabel("次の月")
                    }
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(["月", "火", "水", "木", "金", "土", "日"].enumerated()), id: \.offset) { _, name in
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(0..<(leadingSpaces + days), id: \.self) { index in
                            if index < leadingSpaces { Color.clear.frame(height: 48) }
                            else { dayView(index - leadingSpaces + 1) }
                        }
                    }
                    Text("● クリアした日　✓ きょうの1問を達成")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(calendar.component(.month, from: selectedDay))月\(calendar.component(.day, from: selectedDay))日：\(game.progress.count(on: selectedDay))問クリア" +
                         (game.progress.dailyCompleted(on: selectedDay) ? "・きょうの1問も達成！" : ""))
                        .font(.callout).multilineTextAlignment(.center)
                    Text("この月は\(game.progress.count(in: month))／10問達成")
                        .font(.headline)
                    Text("連続でなくても大丈夫。練習以外の新しい問題を10問解こう。同じ問題の解き直しは数に含めません。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Divider()
                    themePicker
                }.padding(20)
            }
            .background(palette.background).foregroundStyle(palette.foreground)
            .navigationTitle("達成カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
        .tint(palette.accent)
    }

    private func dayView(_ day: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
        let count = game.progress.count(on: date)
        let daily = game.progress.dailyCompleted(on: date)
        let selected = calendar.isDate(date, inSameDayAs: selectedDay)
        return Button { selectedDay = date } label: {
            VStack(spacing: 2) {
                Text("\(day)").font(.callout.bold())
                Image(systemName: daily ? "checkmark" : "circle.fill")
                    .font(.system(size: daily ? 12 : 5))
                    .opacity(daily || count > 0 ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(count > 0 || daily ? palette.accent.opacity(0.2) : palette.soft.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? palette.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day)日、\(count)問クリア" + (daily ? "、きょうの1問達成" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ごほうびの色", systemImage: "gift").font(.headline)
            if game.progress.nightUnlocked {
                Text("「夜空」をプレゼント！一度手に入れた色は、来月も使えます。")
                    .font(.footnote)
                Picker("配色", selection: Binding(get: { game.isNightTheme }, set: { game.selectNightTheme($0) })) {
                    Text("いつもの色").tag(false)
                    Text("夜空").tag(true)
                }.pickerStyle(.segmented)
            } else {
                Label("どこかの月に10問達成で「夜空」が使えます", systemImage: "lock")
                    .font(.footnote)
            }
        }
    }

    private func moveMonth(_ offset: Int) {
        if let next = calendar.date(byAdding: .month, value: offset, to: monthStart) {
            month = next; selectedDay = next
        }
    }
}

#Preview { GameView() }
