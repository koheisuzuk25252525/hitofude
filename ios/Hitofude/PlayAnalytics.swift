import Foundation
import Combine
import FirebaseCore
import FirebaseAnalytics

@MainActor
protocol AnalyticsClient {
    var available: Bool { get }
    func enable()
    func disableAndReset()
    func log(_ name: String, parameters: [String: Any])
}

@MainActor
private final class FirebaseAnalyticsClient: AnalyticsClient {
    private var options: FirebaseOptions? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              options.bundleID == Bundle.main.bundleIdentifier else { return nil }
        return options
    }
    var available: Bool { options != nil }
    func enable() {
        guard let options else { return }
        // Collection is disabled in Info.plist even while Firebase initializes.
        if FirebaseApp.app() == nil { FirebaseApp.configure(options: options) }
        Analytics.setConsent([.analyticsStorage: .granted, .adStorage: .denied,
                              .adUserData: .denied, .adPersonalization: .denied])
        Analytics.setAnalyticsCollectionEnabled(true)
    }
    func disableAndReset() {
        guard FirebaseApp.app() != nil else { return }
        Analytics.setAnalyticsCollectionEnabled(false)
        Analytics.resetAnalyticsData()
        Analytics.setConsent([.analyticsStorage: .denied, .adStorage: .denied,
                              .adUserData: .denied, .adPersonalization: .denied])
    }
    func log(_ name: String, parameters: [String: Any]) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(name, parameters: parameters)
    }
}

enum PlayEvent: String {
    case ready = "puzzle_ready", start = "puzzle_start", hint = "hint_used"
    case complete = "puzzle_complete", leave = "puzzle_leave", restart = "puzzle_restart"
    case pause = "puzzle_pause", resume = "puzzle_resume", restored = "puzzle_restored"
    case generationFailed = "puzzle_generation_failed"
}

@MainActor
protocol PlayEventRecording {
    func record(_ event: PlayEvent, parameters: [String: Any])
}

@MainActor
final class PlayAnalytics: ObservableObject, PlayEventRecording {
    static let shared = PlayAnalytics(defaults: .standard, client: FirebaseAnalyticsClient())
    @Published private(set) var enabled: Bool
    var available: Bool { client.available }
    private let defaults: UserDefaults
    private let client: AnalyticsClient
    private static let consentKey = "hitofude.analyticsConsent.v1"

    init(defaults: UserDefaults, client: AnalyticsClient) {
        self.defaults = defaults
        self.client = client
        enabled = defaults.bool(forKey: Self.consentKey) && client.available
        if enabled { client.enable() }
    }

    func setEnabled(_ value: Bool) {
        let next = value && available
        guard next != enabled else { return }
        enabled = next
        defaults.set(next, forKey: Self.consentKey)
        if next { client.enable() } else { client.disableAndReset() }
    }

    func record(_ event: PlayEvent, parameters: [String: Any]) {
        guard enabled, available else { return }
        client.log(event.rawValue, parameters: parameters)
    }
}
