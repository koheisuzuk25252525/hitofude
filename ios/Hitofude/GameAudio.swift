import AVFoundation
import Combine
import Foundation

// No audio assets or network access: short tones follow the Web version's pitches.
enum GameSound: Equatable {
    case step(index: Int, total: Int)
    case clear
}

@MainActor
protocol GameSoundPlaying {
    func play(_ sound: GameSound)
    func stop()
}

@MainActor
protocol SoundOutput {
    func play(_ data: Data)
    func stop()
}

@MainActor
private final class DeviceSoundOutput: SoundOutput {
    private var players: [AVAudioPlayer] = []

    func play(_ data: Data) {
        do {
            let session = AVAudioSession.sharedInstance()
            // Respect the silent switch and mix with music from other apps.
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            players.removeAll { !$0.isPlaying }
            // Fast strokes may emit many steps; keep latency and memory bounded.
            if players.count >= 4 { players.removeFirst().stop() }
            let player = try AVAudioPlayer(data: data)
            player.volume = 0.35
            if player.play() { players.append(player) }
        } catch {
            // Audio interruptions or unavailable output must never block play.
            stop()
        }
    }

    func stop() {
        players.forEach { $0.stop() }
        players.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
final class GameAudio: ObservableObject, GameSoundPlaying {
    static let shared = GameAudio()
    @Published private(set) var enabled: Bool
    private let defaults: UserDefaults
    private let output: SoundOutput
    private static let key = "hitofude.soundEnabled.v1"

    init(defaults: UserDefaults = .standard, output: SoundOutput? = nil) {
        self.defaults = defaults
        self.output = output ?? DeviceSoundOutput()
        enabled = defaults.object(forKey: Self.key) as? Bool ?? true
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: Self.key)
        if !value { stop() }
    }

    func play(_ sound: GameSound) {
        guard enabled else { return }
        output.play(SoundWave.data(for: sound))
    }

    func stop() { output.stop() }
}

/// 16-bit mono PCM WAV, playable by AVAudioPlayer without external files.
enum SoundWave {
    static let sampleRate = 22_050
    private struct Tone {
        let frequency: Double
        let start: Double
        let duration: Double
        let volume: Double
        var triangle = false
    }

    static func stepFrequency(index: Int, total: Int) -> Double {
        let count = max(2, total)
        return 130.81 * pow(2, 4 * Double(min(max(0, index), count - 1)) / Double(count - 1))
    }

    static func data(for sound: GameSound) -> Data {
        let tones: [Tone]
        switch sound {
        case let .step(index, total):
            let f = stepFrequency(index: index, total: total)
            tones = [Tone(frequency: f, start: 0, duration: 0.20, volume: 0.7, triangle: true),
                     Tone(frequency: f * 2, start: 0, duration: 0.12, volume: 0.14)]
        case .clear:
            tones = [523.25, 659.25, 783.99, 1046.5, 1318.5].enumerated().map { index, f in
                Tone(frequency: f, start: Double(index) * 0.07, duration: 0.6, volume: 0.22, triangle: true)
            } + [Tone(frequency: 2093, start: 0.4, duration: 1.2, volume: 0.12)]
        }
        let duration = tones.map { $0.start + $0.duration }.max() ?? 0
        let frames = Int(ceil(duration * Double(sampleRate)))
        var samples = [Double](repeating: 0, count: frames)
        for tone in tones {
            let start = Int(tone.start * Double(sampleRate))
            let end = min(frames, Int((tone.start + tone.duration) * Double(sampleRate)))
            for frame in start..<end {
                let t = Double(frame - start) / Double(sampleRate)
                let phase = 2 * Double.pi * tone.frequency * t
                let wave = tone.triangle ? (2 / Double.pi) * asin(sin(phase)) : sin(phase)
                let attack = min(1, t / 0.006)
                let release = min(1, max(0, tone.duration - t) / 0.01)
                let envelope = attack * exp(-7 * t / tone.duration) * release
                samples[frame] += wave * envelope * tone.volume
            }
        }
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func u32(_ value: UInt32) {
            u16(UInt16(truncatingIfNeeded: value)); u16(UInt16(truncatingIfNeeded: value >> 16))
        }
        text("RIFF"); u32(UInt32(36 + frames * 2)); text("WAVEfmt ")
        u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2))
        u16(2); u16(16); text("data"); u32(UInt32(frames * 2))
        for sample in samples {
            u16(UInt16(bitPattern: Int16((min(1, max(-1, sample)) * 32767).rounded())))
        }
        return data
    }
}
