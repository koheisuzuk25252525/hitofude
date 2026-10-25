import SwiftUI

struct FeedbackView: View {
    let context: String
    @Environment(\.dismiss) private var dismiss
    @State private var category = "不具合"
    @State private var note = ""
    private let categories = ["不具合", "操作しづらい", "難しすぎる", "よかった", "その他"]

    private var report: String { "【\(category)】\n\(note)\n\n\(context)" }
    private var issueURL: URL {
        var url = URLComponents(string: "https://github.com/koheisuzuk25252525/hitofude/issues/new")!
        url.queryItems = [URLQueryItem(name: "title", value: "[iOS] \(category)"), URLQueryItem(name: "body", value: report)]
        return url.url!
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("気づいたこと") {
                    Picker("種類", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                    TextEditor(text: $note).frame(minHeight: 120)
                        .accessibilityLabel("感想や、問題が起きたときの操作")
                        .onChange(of: note) { _, text in if text.count > 1000 { note = String(text.prefix(1000)) } }
                    Text("操作手順や、どうなってほしかったかを教えてください。個人情報は書かないでください。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("一緒に添える情報") { Text(context).font(.footnote).textSelection(.enabled) }
                Section {
                    ShareLink(item: report) { Label("報告文を共有・コピー", systemImage: "square.and.arrow.up") }
                    Link("GitHubで報告する", destination: issueURL)
                } footer: {
                    Text("自動送信はしません。共有先は自分で選べます。GitHubはアカウントが必要で、投稿すると内容が公開されます。TestFlightのフィードバックにも、この報告文を使えます。")
                }
            }
            .navigationTitle("不具合・感想を送る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}

struct AnalyticsSettingsView: View {
    @ObservedObject var analytics: PlayAnalytics
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("プレイ状況の計測に協力する", isOn: Binding(get: { analytics.enabled }, set: { analytics.setEnabled($0) }))
                        .disabled(!analytics.available)
                    if !analytics.available { Text("このバージョンでは計測は利用できません。プレイには影響しません。").font(.footnote) }
                } footer: {
                    Text("初期設定はオフです。オンにすると、問題開始・ヒント・クリア・中断・復帰、難易度、進捗、プレイ時間をGoogleのFirebase Analyticsに送信し、遊びやすさの改善に使います。オフでもすべての問題を遊べます。")
                }
                Section("送る情報について") {
                    Text("アプリのインストールや一回の挑戦を区別する識別子、端末・OS・アプリの情報も扱います。完全に匿名のデータではありません。氏名、メールアドレス、入力した感想、問題の答えやなぞった経路は計測に送りません。広告目的では利用しません。")
                    Text("オフにすると以降の計測を止め、端末内の計測データと計測用のアプリ識別子をリセットします。ゲームの記録は消えません。すでに送信したデータをGoogle側から削除する操作ではありません。")
                    Link("プライバシーポリシー", destination: URL(string: "https://koheisuzuk25252525.github.io/hitofude/privacy.html")!)
                }
            }
            .navigationTitle("プレイ状況の計測")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
