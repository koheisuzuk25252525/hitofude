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
    @StateObject private var game = GameModel(analytics: PlayAnalytics.shared, sounds: GameAudio.shared)
    @ObservedObject private var audio = GameAudio.shared
    @State private var showsAnalytics = false
    @State private var showsFeedback = false
    @State private var feedbackContext = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsMore = false
    @State private var showsResult = false
    private enum MoreDestination { case feedback, analytics, challenge, progress }
    @State private var pendingDestination: MoreDestination?
    @State private var showsProgress = false
    @State private var showsHelp = false
    private var palette: Palette { Palette(isNight: game.isNightTheme) }
    @State private var showsChallenge = false
    @State private var challengeInput = ""
    @State private var challengeError: String?

    var body: some View {
        ViewThatFits(in: .vertical) {
            PlayScreenLayout(minimumBoardSide: 192) {
                screenHeader
                playArea
                actionDock
            }
            // Large accessibility text / short landscape windows keep actions pinned.
            ScrollView {
                VStack(spacing: 8) {
                    screenHeader
                    playArea.aspectRatio(1, contentMode: .fit)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 8) { actionDock.background(palette.background) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background.ignoresSafeArea())
        .foregroundStyle(palette.foreground)
        .tint(palette.accent)
        .environment(\.hitofudePalette, palette)
        .preferredColorScheme(game.isNightTheme ? .dark : nil)
        .task { await game.startInitialGame() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            updateActivity()
        }
        .onChange(of: showsMore) { _, _ in updateActivity() }
        .onChange(of: showsResult) { _, _ in updateActivity() }
        .sheet(isPresented: $showsMore, onDismiss: openPendingDestination) { moreSheet }
        .sheet(isPresented: $showsResult, onDismiss: openPendingDestination) {
            NavigationStack {
                ScrollView { completion.padding(16) }
                    .navigationTitle("今回の結果")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showsResult = false } } }
            }
        }
        .onChange(of: showsHelp) { _, _ in updateActivity() }
        .onChange(of: showsChallenge) { _, _ in updateActivity() }
        .onChange(of: showsProgress) { _, _ in updateActivity() }
        .onChange(of: showsAnalytics) { _, _ in updateActivity() }
        .onChange(of: showsFeedback) { _, _ in updateActivity() }
        .sheet(isPresented: $showsAnalytics) { AnalyticsSettingsView(analytics: PlayAnalytics.shared) }
        .sheet(isPresented: $showsFeedback) { FeedbackView(context: feedbackContext) }
        .sheet(isPresented: $showsProgress) {
            ProgressCalendarView(game: game)
        }
        .sheet(isPresented: $showsChallenge) { challengeSheet }
        .sheet(isPresented: $showsHelp) {
            NavigationStack {
                ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("ひと筆で、ぜんぶつなごう").font(.title2.bold())
                    Text("1のマスから、上下左右になぞります。ななめには進めません。")
                    Text("数字のあるマスは、その順番に通りましょう。すべてのマスを1回ずつ通ればクリア！")
                    Text("ひとつ前のマスへ戻ると、1手取り消せます。マスを順にタップしても遊べます。")
                    Text("難易度は盤面の上で選べます。効果音は画面上のスピーカーで切り替えます。消音モード中は鳴りません。")
                    Button("れんしゅうする") {
                        showsHelp = false
                        Task { await game.load(.tutorial) }
                    }.buttonStyle(.borderedProminent)
                    Link("プライバシーポリシー", destination: URL(string: "https://koheisuzuk25252525.github.io/hitofude/privacy.html")!)
                    Link("サポート・お問い合わせ", destination: URL(string: "https://koheisuzuk25252525.github.io/hitofude/support.html")!)
                    Text("バージョン \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")（\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")）")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(24)
                }
                .navigationTitle("あそびかた")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showsHelp = false } } }
            }.presentationDetents([.medium, .large])
        }
    }

    private var screenHeader: some View {
        VStack(spacing: 6) {
            header
            DifficultyTabs(selected: game.mode, isLoading: game.isLoading) { mode in
                Task { await game.load(mode) }
            }
            if let greeting = game.returnGreeting {
                Label(greeting.text, systemImage: greeting.symbol).font(.caption).lineLimit(2)
            }
            if let rival = game.rival {
                Text("対戦中：相手 \(GameModel.timeString(TimeInterval(rival.seconds)))")
                    .font(.caption).foregroundStyle(palette.accent)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var playArea: some View {
        if let puzzle = game.puzzle {
            BoardView(game: game, puzzle: puzzle)
                .overlay {
                    if game.isPaused {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18).fill(.regularMaterial)
                            Text("一時停止中").font(.title2.bold())
                        }
                    }
                }
        } else if game.isLoading {
            VStack(spacing: 12) { ProgressView(); Text("問題を作っています…") }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Text(game.message ?? "問題を作れませんでした")
                Button("もう一度") { Task { await game.load(game.mode, seed: game.seed, rival: game.rival) } }
                Button("さくっと一問へ") { Task { await game.load(.easy) } }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actionDock: some View {
        VStack(spacing: 6) {
            if game.isFinished {
                Text("ひと筆、完成！").font(.headline).foregroundStyle(palette.accent)
                HStack {
                    Button(action: nextPuzzle) { Text("もう一問").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("next-puzzle")
                    Button("結果・共有") { showsResult = true }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                }
            } else if game.puzzle != nil {
                if let message = game.message {
                    Text(message).font(.caption).foregroundStyle(palette.accent)
                        .multilineTextAlignment(.center).accessibilityAddTraits(.updatesFrequently)
                }
                controls
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func nextPuzzle() {
        showsResult = false
        Task { await game.load(game.mode == .tutorial ? .easy : game.mode == .daily ? .medium : game.mode) }
    }

    private func chooseMore(_ destination: MoreDestination) {
        pendingDestination = destination
        showsMore = false
    }

    private func openPendingDestination() {
        let destination = pendingDestination
        switch destination {
        case .feedback: showsFeedback = true
        case .analytics: showsAnalytics = true
        case .challenge: showsChallenge = true
        case .progress: showsProgress = true
        case nil: break
        }
        pendingDestination = nil
        updateActivity()
    }

    private var moreSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let best = game.best { Text("\(game.mode.title)のベスト \(GameModel.timeString(best))") }
                    Button("別の問題") {
                        showsMore = false
                        Task { await game.load(game.mode) }
                    }.disabled(game.isLoading)
                    Button("リンクで対戦") { chooseMore(.challenge) }.disabled(game.isLoading)
                    TimelineView(.periodic(from: .now, by: 60)) { context in progressCard(at: context.date) }
                    if let completionMessage = game.completionMessage { Text(completionMessage) }
                    Button("不具合・感想を送る") {
                        feedbackContext = game.feedbackContext
                        chooseMore(.feedback)
                    }
                    Button("プレイ状況の計測") { chooseMore(.analytics) }
                    Text("ヒントは3回。中断中はタイマーが止まります。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationTitle("遊び方・記録・設定")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showsMore = false } } }
        }
    }

    private func updateActivity() {
        let menu = showsHelp || showsChallenge || showsProgress || showsAnalytics || showsFeedback || showsMore || showsResult || pendingDestination != nil
        game.setActive(scenePhase == .active && !menu, reason: scenePhase != .active ? "background" : "menu")
    }

    private func progressCard(at date: Date) -> some View {
        let count = game.progress.count(in: date)
        return Button { chooseMore(.progress) } label: {
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
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                (Text("ヒト") + Text("フデ").foregroundColor(palette.accent))
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Spacer()
                Button { audio.setEnabled(!audio.enabled) } label: {
                    Image(systemName: audio.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.title2).frame(width: 44, height: 44)
                }
                .accessibilityLabel("効果音")
                .accessibilityValue(audio.enabled ? "オン" : "オフ")
                .accessibilityHint(audio.enabled ? "効果音をオフにする" : "効果音をオンにする")
                Button { showsHelp = true } label: {
                    Image(systemName: "questionmark.circle").font(.title2).frame(width: 44, height: 44)
                }.accessibilityLabel("あそびかた")
                Button { showsMore = true } label: {
                    Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44)
                }.accessibilityLabel("遊び方・記録・設定")
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
            Text(game.guidance).font(.caption.bold()).multilineTextAlignment(.center)
            if game.mode == .daily, game.seed != GameMode.dailySeed(), game.puzzle != nil {
                Text("保存した日の問題（\(String(game.seed))）").font(.caption).foregroundStyle(.secondary)
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
            .disabled(game.hintsLeft == 0 || game.highlighted != nil || game.isFinished || game.isPaused || game.mode == .tutorial)
    }
    private var undoButton: some View {
        Button("ひとつ戻す") { game.undo() }.disabled(game.route.isEmpty || game.isFinished)
    }
    private var resetButton: some View {
        Button("やり直す") { game.reset() }
    }
    private var completion: some View {
        VStack(spacing: 14) {
            Text("ひと筆、完成！").font(.title.bold()).foregroundStyle(palette.accent)
            Text("\(game.mode.title)  \(GameModel.timeString(game.elapsed(at: Date())))")
            if let completionMessage = game.completionMessage {
                Text(completionMessage).multilineTextAlignment(.center)
            }
            Button("もう一問", action: nextPuzzle).buttonStyle(.borderedProminent).controlSize(.large)
            if let verdict = game.verdict {
                Text(verdict).font(.headline)
                Button("同じ問題で再挑戦") {
                    showsResult = false
                    Task { await game.load(game.mode, seed: game.seed, rival: game.rival) }
                }.buttonStyle(.bordered)
            }
            if let challenge = game.challenge {
                ShareLink(item: challenge.url,
                          subject: Text("ヒトフデで対戦しよう"),
                          message: Text("\(game.mode.title)・\(GameModel.timeString(TimeInterval(challenge.seconds)))・ヒント使用\(3 - game.hintsLeft)回。このタイムに挑戦！アプリの「リンクで対戦」にリンクを貼り付けてね。")) {
                    Label("挑戦リンクを送る", systemImage: "person.2.wave.2")
                }.buttonStyle(.bordered)
            }
            ShareLink(item: game.shareText) { Label(game.rival == nil ? "結果を共有" : "対戦結果を返信", systemImage: "square.and.arrow.up") }
                .buttonStyle(.bordered)
            Button("達成カレンダーを見る") { showsResult = false; pendingDestination = .progress }
        }
        .padding(20).frame(maxWidth: .infinity)
        .background(palette.soft, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }
}

private struct BoardView: View {
    @Environment(\.hitofudePalette) private var palette
    @ObservedObject var game: GameModel
    let puzzle: Puzzle
    @State private var trace = BoardTrace()
    @GestureState private var isTracing = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let step = width / CGFloat(puzzle.size)
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(palette.cell)
                ForEach(0..<(puzzle.size * puzzle.size), id: \.self) { index in
                    cellView(index: index, step: step)
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
                .updating($isTracing) { _, state, _ in state = true }
                .onChanged { value in
                    for cell in trace.cells(to: value.location, width: width, size: puzzle.size) { game.step(cell) }
                }
                .onEnded { _ in trace.reset() })
            .onChange(of: isTracing) { _, tracing in if !tracing { trace.reset() } }
            .onChange(of: game.isPaused) { _, _ in trace.reset() }
            .onChange(of: game.seed) { _, _ in trace.reset() }
            .onChange(of: width) { _, _ in trace.reset() }
        }
    }

    private func cellView(index: Int, step: CGFloat) -> some View {
        let cell = Cell(row: index / puzzle.size, column: index % puzzle.size)
        let order = game.route.firstIndex(of: cell).map { $0 + 1 }
        let clue = puzzle.clues[cell]
        let clueLabel = clue.map { "数字\($0)" } ?? "空白"
        let orderLabel = order.map { "、\($0)番目に通過" } ?? ""
        let isTarget = clue != nil && clue == game.nextClue
        let isHint = game.highlighted == cell
        let hintLabel = isHint ? "ヒント：次に進むマス" : isTarget ? "次に目指す数字" : ""
        return Button { game.step(cell) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHint ? palette.accent.opacity(0.35) :
                          order != nil ? palette.accent.opacity(0.16) : palette.soft.opacity(0.5))
                if let number = clue ?? order {
                    Text("\(number)")
                        .font(.system(size: max(14, step * 0.38), weight: clue != nil ? .bold : .regular, design: .rounded))
                        .foregroundStyle(palette.foreground)
                }
                if isHint {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(palette.accent, lineWidth: 3)
                    VStack { HStack { Spacer(); Text("\(game.route.count + 1)").font(.caption2.bold()).padding(3).background(palette.accent, in: Capsule()).foregroundStyle(palette.background) }; Spacer() }
                } else if isTarget {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(palette.foreground.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [3]))
                }
            }
            .frame(width: max(1, step - 6), height: max(1, step - 6))
        }
        .buttonStyle(.plain)
        .position(center(of: cell, step: step))
        .accessibilityLabel("\(cell.row + 1)行\(cell.column + 1)列、\(clueLabel)\(orderLabel)")
        .accessibilityHint(hintLabel)
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

struct DifficultyTabs: View {
    let selected: GameMode
    let isLoading: Bool
    let select: (GameMode) -> Void
    @Environment(\.hitofudePalette) private var palette

    // All five modes remain visible; narrow screens and large text wrap into rows.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("難易度・きょうの1問").font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(playModes) { mode in modeButton(mode).fixedSize(horizontal: true, vertical: false) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(playModes) { mode in modeButton(mode) }
                }
            }
        }
    }

    private var playModes: [GameMode] { [.daily, .easy, .medium, .hard, .oni] }

    private func modeButton(_ mode: GameMode) -> some View {
        Button { select(mode) } label: {
            Text(mode.title).font(.subheadline.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected == mode ? palette.accent : palette.soft, in: Capsule())
                .foregroundStyle(selected == mode ? palette.background : palette.foreground)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == mode ? .isSelected : [])
        .accessibilityIdentifier("mode-" + mode.rawValue)
        .disabled(isLoading)
    }

}

/// Reserve the header and actions before giving the board the remaining square.
/// Report a minimum height so ViewThatFits can use the accessible scrolling fallback.
struct PlayScreenGeometry {
    let size: CGSize
    let header: CGRect
    let board: CGRect
    let footer: CGRect

    init(width: CGFloat, height: CGFloat?, headerHeight: CGFloat, footerHeight: CGFloat,
         minimumBoardSide: CGFloat = 192) {
        let width = max(0, width)
        let minimum = headerHeight + footerHeight + min(width, minimumBoardSide) + 16
        let height = max(height ?? minimum, minimum)
        size = CGSize(width: width, height: height)
        let side = floor(min(width, height - headerHeight - footerHeight - 16))
        header = CGRect(x: 0, y: 0, width: width, height: headerHeight)
        footer = CGRect(x: 0, y: height - footerHeight, width: width, height: footerHeight)
        board = CGRect(x: (width - side) / 2,
                       y: headerHeight + 8 + (height - headerHeight - footerHeight - 16 - side) / 2,
                       width: side, height: side)
    }
}

struct PlayScreenLayout: Layout {
    var minimumBoardSide: CGFloat = 192

    private func geometry(_ proposal: ProposedViewSize, subviews: Subviews) -> PlayScreenGeometry {
        let width = proposal.width ?? 536
        let sizing = ProposedViewSize(width: width, height: nil)
        return PlayScreenGeometry(width: width, height: proposal.height,
                                  headerHeight: subviews[0].sizeThatFits(sizing).height,
                                  footerHeight: subviews[2].sizeThatFits(sizing).height,
                                  minimumBoardSide: minimumBoardSide)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        geometry(proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = geometry(ProposedViewSize(bounds.size), subviews: subviews)
        for (index, frame) in [plan.header, plan.board, plan.footer].enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}
