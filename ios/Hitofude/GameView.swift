import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

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
    @StateObject private var rewardedHints = RewardedHints()
    @State private var showsRewardOffer = false
    @ObservedObject private var audio = GameAudio.shared
    @State private var showsAnalytics = false
    @State private var showsFeedback = false
    @State private var feedbackContext = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
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

    private var playingScreen: some View {
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
    }

    var body: some View {
        ZStack {
            playingScreen
                .allowsHitTesting(!showsResult && !rewardedHints.isBusy)
                .accessibilityHidden(showsResult)
            if showsResult && game.isFinished {
                Color.black.opacity(0.2).ignoresSafeArea()
                    .accessibilityHidden(true)
                completion.padding(12)
            }
        }
        .overlay {
            if rewardedHints.isLoading {
                VStack(spacing: 16) {
                    ProgressView("広告を読み込んでいます")
                    Button("キャンセル") { rewardedHints.cancelLoading() }
                }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .onChange(of: rewardedHints.isBusy) { _, _ in updateActivity() }
        .onChange(of: showsRewardOffer) { _, _ in updateActivity() }
        .alert("スーパーヒント", isPresented: $showsRewardOffer) {
            Button("広告を見る") { showRewardedHint() }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("広告を最後まで見ると、ゴールまでの正しい順番を表示します。自己ベストの対象にはなりません。\n現在はテスト広告です。Googleの広告SDKが通信し、IPアドレス・端末情報・広告操作情報などを扱います。プレイ分析への同意とは別の機能です。")
        }
        .alert("広告を表示できません", isPresented: Binding(get: { rewardedHints.error != nil }, set: { if !$0 { rewardedHints.error = nil } })) {
            Button("閉じる", role: .cancel) { rewardedHints.error = nil }
        } message: { Text(rewardedHints.error ?? "") }
        .foregroundStyle(palette.foreground)
        .tint(palette.accent)
        .environment(\.hitofudePalette, palette)
        .preferredColorScheme(game.isNightTheme ? .dark : nil)
        .task { await game.startInitialGame() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            updateActivity()
        }
        .onChange(of: showsMore) { _, _ in updateActivity() }
        .sheet(isPresented: $showsMore, onDismiss: openPendingDestination) { moreSheet }
        .onChange(of: game.isFinished) { _, finished in showsResult = finished }
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
                    Text("ヒントは1問につき3回。やり直しても回数は戻りません。使い切った後は、任意のテスト広告を最後まで見ると全マスの正しい順番を表示できます。広告表示にはGoogleへの通信が必要です。スーパーヒント使用時は自己ベストの対象外です。")
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
            DifficultySelector(selected: game.mode, isLoading: game.isLoading) { mode in
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
                    if game.isPaused && !game.isFinished {
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
        ZStack {
            if game.puzzle != nil {
                // Retain the same layout height on completion; the board must not jump.
                controls
                    .opacity(game.isFinished ? 0 : 1)
                    .allowsHitTesting(!game.isFinished)
                    .accessibilityHidden(game.isFinished)
                if game.isFinished && !showsResult {
                    Button("結果を表示") { showsResult = true }
                        .frame(minHeight: 44)
                        .buttonStyle(.bordered)
                }
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
        // Results only appear after finish() has frozen the clock. Do not interrupt the clear sound.
        let menu = showsHelp || showsChallenge || showsProgress || showsAnalytics || showsFeedback || showsMore || pendingDestination != nil || showsRewardOffer || rewardedHints.isBusy
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
            Text(game.message ?? game.guidance).font(.caption.bold()).multilineTextAlignment(.center)
                .foregroundStyle(game.message == nil ? palette.foreground : palette.accent)
                .lineLimit(typeSize.isAccessibilitySize ? 8 : 2, reservesSpace: !typeSize.isAccessibilitySize)
                .accessibilityAddTraits(.updatesFrequently)
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
    @ViewBuilder private var hintButton: some View {
        if game.hintsLeft == 0 {
            Button(game.superHintUnlocked ? "道順を表示中" : "スーパーヒント") { showsRewardOffer = true }
                .disabled(!game.canRequestSuperHint || game.isPaused || rewardedHints.isBusy)
        } else {
            Button("ヒント \(game.hintsLeft)") { game.hint() }
                .disabled(game.highlighted != nil || game.isFinished || game.isPaused || game.mode == .tutorial)
        }
    }
    private func showRewardedHint() {
        guard let token = game.beginSuperHintReward() else { return }
        rewardedHints.show(reward: { _ = game.earnSuperHint(token) },
                           completion: { game.cancelSuperHintReward(token) })
        updateActivity()
    }
    private var undoButton: some View {
        Button("ひとつ戻す") { game.undo() }.disabled(game.route.isEmpty || game.isFinished)
    }
    private var resetButton: some View {
        Button("やり直す") { game.reset() }
    }
    private var completion: some View {
        CompletionPanel(
            summary: "\(game.mode.title)  \(GameModel.timeString(game.elapsed(at: Date())))",
            message: game.completionMessage,
            verdict: game.verdict,
            challengeURL: game.challenge?.url,
            challengeMessage: "\(game.mode.title)・\(GameModel.timeString(TimeInterval(game.challenge?.seconds ?? 0)))・ヒント使用\(3 - game.hintsLeft)回。このタイムに挑戦！アプリの「リンクで対戦」にリンクを貼り付けてね。",
            shareText: game.shareText,
            next: nextPuzzle,
            retry: {
                showsResult = false
                Task { await game.load(game.mode, seed: game.seed, rival: game.rival) }
            },
            calendar: { showsProgress = true },
            dismiss: { showsResult = false }
        )
    }

}

/// A screen overlay, independent of the board's size and any underlying scroll position.
struct CompletionPanel: View {
    @Environment(\.hitofudePalette) private var palette
    @AccessibilityFocusState private var titleFocused: Bool
    let summary: String
    let message: String?
    let verdict: String?
    let challengeURL: URL?
    let challengeMessage: String
    let shareText: String
    let next: () -> Void
    let retry: () -> Void
    let calendar: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            // All actions fit together at standard text sizes on portrait iPhones.
            fullContent.fixedSize(horizontal: false, vertical: true)
            // Large accessibility text / landscape retain a reachable next action.
            ScrollView {
                VStack(spacing: 8) { details; secondaryActions }
                    .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top, spacing: 8) { heading }
            .safeAreaInset(edge: .bottom, spacing: 8) { nextButton }
        }
        .padding(16)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(palette.foreground.opacity(0.18)))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { titleFocused = true }
    }

    // Exposed internally so tests measure the full, non-scrolling content, not a clipped container.
    var fullContent: some View {
        VStack(spacing: 8) { heading; details; nextButton; secondaryActions }
    }

    private var heading: some View {
        HStack(spacing: 4) {
            Text("ひと筆、完成！").font(.title2.bold())
                .foregroundStyle(palette.accent)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill").font(.title2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("結果を閉じて盤面を見る")
        }
    }

    private var details: some View {
        VStack(spacing: 4) {
            Text(summary).font(.headline)
            if let message { Text(message).font(.subheadline) }
            if let verdict { Text(verdict).font(.headline) }
        }.multilineTextAlignment(.center)
    }

    private var nextButton: some View {
        Button(action: next) {
            Text("もう一問").bold().frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("completion-next-puzzle")
    }

    private var secondaryActions: some View {
        VStack(spacing: 4) {
            if verdict != nil {
                Button(action: retry) {
                    Text("同じ問題で再挑戦").frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            if let challengeURL {
                ShareLink(item: challengeURL, subject: Text("ヒトフデで対戦しよう"), message: Text(challengeMessage)) {
                    Label("挑戦リンクを送る", systemImage: "person.2.wave.2")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            ShareLink(item: shareText) {
                Label(verdict == nil ? "結果を共有" : "対戦結果を返信", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            Button(action: calendar) {
                Text("達成カレンダーを見る").frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }
}

// Receive coalesced UIKit samples without publishing per-pixel SwiftUI state.
private struct BoardTouchSurface: UIViewRepresentable {
    let size: Int
    let identifier: UInt32
    let enabled: Bool
    let onCells: ([Cell]) -> Void

    func makeUIView(context: Context) -> BoardTouchView { BoardTouchView() }

    func updateUIView(_ view: BoardTouchView, context: Context) {
        if view.input.boardSize != size || view.input.identifier != identifier {
            view.input.cancelStroke()
        }
        view.input.boardSize = size
        view.input.identifier = identifier
        view.input.onCells = onCells
        view.isUserInteractionEnabled = enabled
        if view.input.isEnabled != enabled { view.input.isEnabled = enabled }
    }
}

private final class BoardTouchView: UIView {
    let input = BoardStrokeRecognizer(target: nil, action: nil)
    private var previousSize: CGSize = .zero

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        accessibilityElementsHidden = true
        input.cancelsTouchesInView = true
        input.delaysTouchesBegan = false
        addGestureRecognizer(input)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != previousSize { input.cancelStroke(); previousSize = bounds.size }
    }
}

private final class BoardStrokeRecognizer: UIGestureRecognizer {
    var boardSize = 0
    var identifier: UInt32 = 0
    var onCells: (([Cell]) -> Void)?
    private var activeTouch: UITouch?
    private var trace = BoardTrace()

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        trace.reset()
        state = .began // Claim the board immediately rather than waiting for a scroll threshold.
        consume(touch, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        state = .changed
        consume(touch, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        consume(touch, event: event)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { cancelStroke() }

    override func reset() {
        super.reset()
        trace.reset()
        activeTouch = nil
    }

    func cancelStroke() {
        if activeTouch != nil { state = .cancelled }
        trace.reset()
        activeTouch = nil
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false // The scroll fallback must not steal a stroke that began on the board.
    }

    private func consume(_ touch: UITouch, event: UIEvent) {
        guard let view else { return }
        let history = event.coalescedTouches(for: touch) ?? []
        let samples = (history.isEmpty ? [touch] : history).map { $0.location(in: view) }
        let cells = trace.cells(samples: samples, width: view.bounds.width, size: boardSize)
        if !cells.isEmpty { onCells?(cells) }
    }
}

private struct BoardView: View {
    @Environment(\.hitofudePalette) private var palette
    @ObservedObject var game: GameModel
    let puzzle: Puzzle

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let step = width / CGFloat(puzzle.size)
            let orders = Dictionary(uniqueKeysWithValues: game.route.enumerated().map { ($0.element, $0.offset + 1) })
            let solution = game.superHintUnlocked ? Dictionary(uniqueKeysWithValues: puzzle.path.enumerated().map { ($0.element, $0.offset + 1) }) : [:]
            let nextClue = game.nextClue
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(palette.cell)
                ForEach(0..<(puzzle.size * puzzle.size), id: \.self) { index in
                    cellView(index: index, step: step, order: orders[Cell(row: index / puzzle.size, column: index % puzzle.size)], nextClue: nextClue, solution: solution[Cell(row: index / puzzle.size, column: index % puzzle.size)])
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
            .overlay {
                BoardTouchSurface(size: puzzle.size, identifier: game.seed,
                                  enabled: !game.isPaused && !game.isFinished && !game.isLoading,
                                  onCells: game.trace)
                    .accessibilityHidden(true)
            }
        }
    }

    private func cellView(index: Int, step: CGFloat, order: Int?, nextClue: Int?, solution: Int?) -> some View {
        let cell = Cell(row: index / puzzle.size, column: index % puzzle.size)
        let clue = solution ?? puzzle.clues[cell]
        let clueLabel = clue.map { "数字\($0)" } ?? "空白"
        let orderLabel = order.map { "、\($0)番目に通過" } ?? ""
        let isTarget = clue != nil && clue == nextClue
        let isHint = game.highlighted == cell
        let hintLabel = isHint ? "ヒント：\(game.hintNumber ?? game.route.count + 1)番目に進むマス" : isTarget ? "次に目指す数字" : ""
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
                    VStack { HStack { Spacer(); Text("\(game.hintNumber ?? game.route.count + 1)").font(.caption2.bold()).padding(3).background(palette.accent, in: Capsule()).foregroundStyle(palette.background) }; Spacer() }
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

struct DifficultySelector: View {
    let selected: GameMode
    let isLoading: Bool
    let select: (GameMode) -> Void
    @Environment(\.hitofudePalette) private var palette

    var body: some View {
        Menu {
            ForEach([GameMode.daily, .easy, .medium, .hard, .oni]) { mode in
                Button { select(mode) } label: {
                    if selected == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
                .accessibilityIdentifier("mode-" + mode.rawValue)
            }
        } label: {
            HStack(spacing: 8) {
                Text("難易度").foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(selected.title).bold()
                Image(systemName: "chevron.down").font(.caption.bold())
            }
            .font(.subheadline)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(palette.soft, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(palette.foreground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("難易度")
        .accessibilityValue(selected.title)
        .accessibilityHint("タップして難易度や、きょうの1問を選びます")
        .accessibilityIdentifier("difficulty-selector")
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
        let width = width.isFinite ? max(0, width) : 536
        let proposedHeight = height.flatMap { $0.isFinite ? $0 : nil }
        let minimum = headerHeight + footerHeight + min(width, minimumBoardSide) + 16
        let height = max(proposedHeight ?? minimum, minimum)
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
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 536
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
