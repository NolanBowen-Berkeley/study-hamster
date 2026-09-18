import AppKit
import AVFoundation

/// Plays the hamster's alerts: a synthesized squeak or one of the built-in macOS sounds.
@MainActor
final class SoundPlayer {
    static let squeak = "Squeak"
    /// Everything offered in Settings. All but the squeak are system sounds (/System/Library/Sounds).
    static let choices = [squeak, "Glass", "Hero", "Ping", "Purr", "Submarine", "Funk"]

    private lazy var squeakWAV = SqueakSynthesizer.makeWAV()
    // Strong references: a player that gets deallocated stops mid-sound.
    private var audioPlayer: AVAudioPlayer?
    private var systemSound: NSSound?
    private var repeatWork: DispatchWorkItem?

    /// Plays `name` `times` times in a row, replacing whatever is still playing.
    func play(_ name: String, times: Int = 1) {
        stop()
        let times = max(1, times)
        if name != Self.squeak, NSSound(named: NSSound.Name(name)) != nil {
            playSystemSound(name, remaining: times)
        } else {
            playSqueak(times: times)
        }
    }

    func stop() {
        repeatWork?.cancel()
        repeatWork = nil
        audioPlayer?.stop()
        audioPlayer = nil
        systemSound?.stop()
        systemSound = nil
    }

    private func playSqueak(times: Int) {
        guard let player = try? AVAudioPlayer(data: squeakWAV) else { return }
        player.numberOfLoops = times - 1  // the WAV ends in a short silence, so loops are spaced out
        player.play()
        audioPlayer = player
    }

    private func playSystemSound(_ name: String, remaining: Int) {
        // `NSSound(named:)` returns a shared instance; play a copy so a replay never fails because the
        // shared one is still playing.
        guard remaining > 0, let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        sound.play()
        systemSound = sound
        guard remaining > 1 else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.playSystemSound(name, remaining: remaining - 1) }
        }
        repeatWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + sound.duration + 0.15, execute: work)
    }
}

/// Builds a tiny 16-bit mono PCM WAV in memory: two quick rising chirps (~1.8 → 3.4 kHz) with a soft
/// envelope and a touch of vibrato — a hamster "squeak-squeak".
enum SqueakSynthesizer {
    private struct Chirp {
        var start: Double
        var duration: Double
        var fromHz: Double
        var toHz: Double
    }

    static func makeWAV(sampleRate: Int = 44_100) -> Data {
        let rate = Double(sampleRate)
        let chirps = [
            Chirp(start: 0.00, duration: 0.085, fromHz: 1_800, toHz: 3_000),
            Chirp(start: 0.13, duration: 0.11, fromHz: 2_000, toHz: 3_400),
        ]
        let totalSeconds = 0.42  // includes trailing silence so looped repeats don't run together
        var buffer = [Double](repeating: 0, count: Int(totalSeconds * rate))

        for chirp in chirps {
            let count = Int(chirp.duration * rate)
            let offset = Int(chirp.start * rate)
            var phase = 0.0
            for i in 0..<count where offset + i < buffer.count {
                let t = Double(i) / Double(count)
                let sweep = t * t * (3 - 2 * t)  // smoothstep: eases into and out of the rise
                let vibrato = 1 + 0.02 * sin(2 * .pi * 38 * Double(i) / rate)
                let frequency = (chirp.fromHz + (chirp.toHz - chirp.fromHz) * sweep) * vibrato
                phase += 2 * .pi * frequency / rate
                let envelope = pow(sin(.pi * t), 0.7)
                let tone = sin(phase) + 0.22 * sin(2 * phase) + 0.06 * sin(3 * phase)
                buffer[offset + i] += 0.3 * envelope * tone
            }
        }

        let samples = buffer.map { Int16(max(-1, min(1, $0)) * Double(Int16.max)) }
        return wavData(samples: samples, sampleRate: sampleRate)
    }

    private static func wavData(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        func appendASCII(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        let bytesPerSample = 2
        let dataSize = UInt32(samples.count * bytesPerSample)
        appendASCII("RIFF")
        append32(36 + dataSize)
        appendASCII("WAVE")
        appendASCII("fmt ")
        append32(16)  // PCM header size
        append16(1)  // PCM format
        append16(1)  // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * bytesPerSample))  // byte rate
        append16(UInt16(bytesPerSample))  // block align
        append16(16)  // bits per sample
        appendASCII("data")
        append32(dataSize)
        for sample in samples {
            append16(UInt16(bitPattern: sample))
        }
        return data
    }
}
