import AVFoundation
import Foundation

/// Tiny procedural sound engine. No audio assets, no third-party packages.
/// The engine hum is a looping buffer; one-shots use a small player pool.
@MainActor
final class AudioEngine {
    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private let enginePlayer = AVAudioPlayerNode()
    private var oneShotPlayers: [AVAudioPlayerNode] = []
    private var nextOneShot = 0

    private var engineBuffer: AVAudioPCMBuffer?
    private var boostBuffer: AVAudioPCMBuffer?
    private var ringBuffer: AVAudioPCMBuffer?
    private var perfectRingBuffer: AVAudioPCMBuffer?
    private var nearMissBuffer: AVAudioPCMBuffer?
    private var crashBuffer: AVAudioPCMBuffer?
    private var fanSaveBuffer: AVAudioPCMBuffer?
    private var flipBuffer: AVAudioPCMBuffer?

    private let sampleRate: Double = 44_100
    private var isPrepared = false
    private var engineRunning = false

    private init() {}

    // MARK: - Public

    func startEngine() {
        guard soundEnabled else { return }
        prepareIfNeeded()
        guard let engineBuffer else { return }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                return
            }
        }

        if !engineRunning {
            enginePlayer.scheduleBuffer(engineBuffer, at: nil, options: .loops)
            enginePlayer.play()
            engineRunning = true
        }
        enginePlayer.volume = 0.14
    }

    func stopEngine() {
        guard engineRunning else { return }
        enginePlayer.volume = 0
        enginePlayer.pause()
        engineRunning = false
    }

    func setSpeed(_ speed: Float, boosting: Bool) {
        guard engineRunning else { return }
        let normalized = min(1.5, max(0.7, speed / 70))
        enginePlayer.rate = normalized * (boosting ? 1.18 : 1.0)
        enginePlayer.volume = boosting ? 0.2 : 0.14
    }

    func setBoost(_ active: Bool) {
        if active {
            play(boostBuffer, volume: 0.5)
        }
    }

    func ring(perfect: Bool) {
        play(perfect ? perfectRingBuffer : ringBuffer, volume: perfect ? 0.55 : 0.4)
    }

    func nearMiss() {
        play(nearMissBuffer, volume: 0.4)
    }

    func crash() {
        play(crashBuffer, volume: 0.7)
    }

    func fanSave() {
        play(fanSaveBuffer, volume: 0.55)
    }

    func flip() {
        play(flipBuffer, volume: 0.45)
    }

    func finish() {
        ring(perfect: true)
    }

    // MARK: - Setup

    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: "Roadster.sound") as? Bool ?? true
    }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        isPrepared = true

        // Mix with any music the player already has going, and respect the
        // silent switch like a normal game.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        )!

        engine.attach(enginePlayer)
        engine.connect(enginePlayer, to: engine.mainMixerNode, format: format)

        for _ in 0..<5 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            oneShotPlayers.append(player)
        }

        engine.mainMixerNode.outputVolume = 0.9
        engineBuffer = makeEngineHum(format: format)
        boostBuffer = makeBoost(format: format)
        ringBuffer = makeRing(format: format, base: 880)
        perfectRingBuffer = makeRing(format: format, base: 1_320)
        nearMissBuffer = makeNearMiss(format: format)
        crashBuffer = makeCrash(format: format)
        fanSaveBuffer = makeFanSave(format: format)
        flipBuffer = makeFlip(format: format)
    }

    private func play(_ buffer: AVAudioPCMBuffer?, volume: Float) {
        guard soundEnabled, let buffer else { return }
        prepareIfNeeded()
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        guard !oneShotPlayers.isEmpty else { return }
        let player = oneShotPlayers[nextOneShot % oneShotPlayers.count]
        nextOneShot += 1
        player.stop()
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
    }

    // MARK: - Buffer synthesis

    private func makeBuffer(
        format: AVAudioFormat,
        duration: Double,
        sample: (Double) -> Float
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return nil }
        buffer.frameLength = frameCount
        guard let data = buffer.floatChannelData?[0] else { return nil }
        for index in 0..<Int(frameCount) {
            data[index] = max(-1, min(1, sample(Double(index) / sampleRate)))
        }
        return buffer
    }

    private func makeEngineHum(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        makeBuffer(format: format, duration: 2.0) { t in
            let fundamental = sin(2 * .pi * 55 * t) * 0.32
            let harmonic = sin(2 * .pi * 110 * t + 0.4) * 0.14
            let whine = sin(2 * .pi * 440 * t) * 0.035
            let shimmer = sin(2 * .pi * 880 * t + 1.1) * 0.018
            return Float(fundamental + harmonic + whine + shimmer)
        }
    }

    private func makeBoost(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        makeBuffer(format: format, duration: 0.55) { t in
            let envelope = exp(-t * 3.2)
            let noise = sin(2 * .pi * 2_200 * t) * 0.4
                + sin(2 * .pi * 3_100 * t + 0.7) * 0.3
            let rise = sin(2 * .pi * (180 + 900 * t) * t) * 0.35
            return Float((noise + rise) * envelope)
        }
    }

    private func makeRing(format: AVAudioFormat, base: Double) -> AVAudioPCMBuffer? {
        makeBuffer(format: format, duration: 0.4) { t in
            let envelope = exp(-t * 8)
            let a = sin(2 * .pi * base * t)
            let b = sin(2 * .pi * base * 1.5 * t) * 0.5
            return Float((a + b) * envelope * 0.55)
        }
    }

    private func makeNearMiss(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        makeBuffer(format: format, duration: 0.35) { t in
            let envelope = sin(min(1, t / 0.35) * .pi)
            let noise = sin(2 * .pi * (1_400 + 2_000 * t) * t) * 0.35
            return Float(noise * envelope)
        }
    }

    private func makeCrash(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        makeBuffer(format: format, duration: 0.8) { t in
            let envelope = exp(-t * 4.2)
            let noise = sin(2 * .pi * 93 * t) * 0.5
                + sin(2 * .pi * 147 * t + 0.8) * 0.3
                + sin(2 * .pi * 610 * t) * 0.18
            return Float(noise * envelope)
        }
    }

    private func makeFanSave(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        makeBuffer(format: format, duration: 0.45) { t in
            let envelope = sin(min(1, t / 0.45) * .pi)
            let frequency = 440 + 880 * (t / 0.45)
            return Float(sin(2 * .pi * frequency * t) * envelope * 0.45)
        }
    }

    private func makeFlip(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        makeBuffer(format: format, duration: 0.3) { t in
            let envelope = sin(min(1, t / 0.3) * .pi)
            let frequency = 300 + 1_200 * (t / 0.3)
            return Float(sin(2 * .pi * frequency * t) * envelope * 0.4)
        }
    }
}
