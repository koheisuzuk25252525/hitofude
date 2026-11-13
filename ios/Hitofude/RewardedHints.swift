import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform
import StoreKit

enum AdPlacement {
    static let test = "ca-app-pub-3940256099942544/1712485313"
    static let production = "ca-app-pub-2673589317149443/7093941165"

    static func unitID(isDebug: Bool, verifiedProduction: Bool) -> String {
        !isDebug && verifiedProduction ? production : test
    }

    static func current() async -> String {
        #if DEBUG
        return test
        #else
        // Fail closed: TestFlight, local installs and unverifiable transactions use test ads.
        guard Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") == nil,
              let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result else { return test }
        return unitID(isDebug: false, verifiedProduction: transaction.environment == .production)
        #endif
    }
}

@MainActor
protocol AdConsentProviding {
    func refresh() async -> Bool
    func presentIfRequired() async throws
    func presentPrivacyOptions() async throws
    var canRequestAds: Bool { get }
    var requiresPrivacyOptions: Bool { get }
}

/// Consent information is refreshed each launch, without initializing the advertising SDK.
@MainActor
final class AdConsent: AdConsentProviding {
    var canRequestAds: Bool { ConsentInformation.shared.canRequestAds }
    var requiresPrivacyOptions: Bool { ConsentInformation.shared.privacyOptionsRequirementStatus == .required }
    func presentIfRequired() async throws { try await ConsentForm.loadAndPresentIfRequired(from: nil) }
    func presentPrivacyOptions() async throws { try await ConsentForm.presentPrivacyOptionsForm(from: nil) }
    static let shared = AdConsent()
    private var update: Task<Bool, Never>?

    func refresh() async -> Bool {
        if let update { return await update.value }
        let task = Task { @MainActor in
            await withCheckedContinuation { continuation in
                ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { error in
                    continuation.resume(returning: error == nil)
                }
            }
        }
        update = task
        let success = await task.value
        update = nil
        return success
    }
}

@MainActor
final class RewardedHints: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var isBusy = false
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published private(set) var usesTestAds = true
    private let consent: AdConsentProviding
    private let isActive: () -> Bool
    init(consent: AdConsentProviding? = nil, isActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }) {
        self.isActive = isActive
        self.consent = consent ?? AdConsent.shared
        super.init()
    }
    private var ad: RewardedAd?
    private var requestID: UUID?
    private var reward: (() -> Void)?
    private var completion: (() -> Void)?
    private var timeout: Task<Void, Never>?

    func prepare() async {
        let unit = await AdPlacement.current()
        usesTestAds = unit == AdPlacement.test
        _ = await consent.refresh()
    }

    func showPrivacyOptions() {
        guard !isBusy else { return }
        let id = UUID()
        requestID = id
        isBusy = true
        isLoading = true
        error = nil
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.requestID == id, self.isLoading else { return }
            self.fail()
        }
        Task { @MainActor in
            let refreshed = await consent.refresh()
            guard self.requestID == id else { return }
            defer { self.finish() }
            guard refreshed, self.isActive() else {
                self.error = "広告の設定を確認できませんでした。通信環境を確認してお試しください。"
                return
            }
            self.timeout?.cancel()
            self.isLoading = false
            do {
                if consent.requiresPrivacyOptions {
                    try await consent.presentPrivacyOptions()
                } else {
                    try await consent.presentIfRequired()
                    if !consent.requiresPrivacyOptions {
                        self.error = "現在の地域では、変更できる広告の同意設定はありません。広告は任意で、非パーソナライズ方式です。"
                    }
                }
            } catch {
                self.error = "広告の設定を表示できませんでした。時間をおいてお試しください。"
            }
        }
    }

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
            let refreshed = await consent.refresh()
            guard self.requestID == id else { return }
            guard refreshed, self.isActive() else { self.fail(); return }
            // Do not time out or allow another presentation while a consent form is open.
            self.timeout?.cancel()
            self.isLoading = false
            do {
                try await consent.presentIfRequired()
            } catch {
                guard self.requestID == id else { return }
                self.fail()
                return
            }
            guard self.requestID == id else { return }
            guard consent.canRequestAds,
                  self.isActive() else { self.fail(); return }
            self.isLoading = true
            self.timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.requestID == id, self.isLoading else { return }
                self.fail()
            }
            let unitID = await AdPlacement.current()
            guard self.requestID == id else { return }
            self.usesTestAds = unitID == AdPlacement.test
            // No SDK initialization or ad requests until UMP permits them.
            _ = await MobileAds.shared.start()
            guard self.requestID == id else { return }
            let request = Request()
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
            do {
                let loaded = try await RewardedAd.load(
                    with: unitID, request: request)
                guard self.requestID == id else { return }
                guard self.isActive() else { self.finish(); return }
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
