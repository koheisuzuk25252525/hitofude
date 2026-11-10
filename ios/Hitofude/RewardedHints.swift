import SwiftUI
import GoogleMobileAds

/// Only Google's official test placement is permitted in this beta.
@MainActor
final class RewardedHints: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var isBusy = false
    @Published private(set) var isLoading = false
    @Published var error: String?
    private var ad: RewardedAd?
    private var requestID: UUID?
    private var reward: (() -> Void)?
    private var completion: (() -> Void)?
    private var timeout: Task<Void, Never>?

    func show(reward: @escaping () -> Void, completion: @escaping () -> Void) {
        guard !isBusy else { return }
        let id = UUID()
        requestID = id
        self.reward = reward
        self.completion = completion
        error = nil
        isBusy = true
        isLoading = true
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.requestID == id, self.isLoading else { return }
            self.fail()
        }
        Task { [weak self] in
            guard let self else { return }
            // No SDK initialization or ad requests until the player explicitly opts in.
            MobileAds.shared.start()
            let request = Request()
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
            do {
                let loaded = try await RewardedAd.load(
                    with: "ca-app-pub-3940256099942544/1712485313", request: request)
                guard self.requestID == id else { return }
                guard UIApplication.shared.applicationState == .active else { self.finish(); return }
                self.timeout?.cancel()
                self.ad = loaded
                loaded.fullScreenContentDelegate = self
                self.isLoading = false
                loaded.present(from: nil) { [weak self] in
                    guard let self, self.requestID == id else { return }
                    // Consumed once, and only from the SDK's earned-reward callback.
                    let grant = self.reward
                    self.reward = nil
                    grant?()
                }
            } catch {
                guard self.requestID == id else { return }
                self.fail()
            }
        }
    }

    func cancelLoading() { if isLoading { finish() } }
    private func fail() {
        finish()
        error = "広告を読み込めませんでした。通信環境を確認して、もう一度お試しください。"
    }
    private func finish() {
        timeout?.cancel()
        timeout = nil
        requestID = nil
        ad = nil
        reward = nil
        let done = completion
        completion = nil
        isLoading = false
        isBusy = false
        done?()
    }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) { finish() }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { fail() }
}
