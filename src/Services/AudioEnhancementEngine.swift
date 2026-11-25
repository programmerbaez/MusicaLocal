// Motor experimental de audio. macOS 12 / Swift 5.7.
// No sustituye el motor AVAudioPlayer: se usa solo si el usuario lo activa.
import Foundation
import AVFoundation

enum AudioProfile: String, CaseIterable, Identifiable {
    case flat, balanced, bass, vocals
    var id: String { rawValue }
    var label: String {
        switch self {
        case .flat: return "Original"
        case .balanced: return "Equilibrado"
        case .bass: return "Graves"
        case .vocals: return "Voces"
        }
    }
    var gains: [Float] {
        switch self {
        case .flat: return [0, 0, 0, 0, 0]
        case .balanced: return [1.0, 0.5, 0, 0.7, 0.9]
        case .bass: return [3.0, 2.0, -0.5, 0, 0]
        case .vocals: return [-1.0, -0.5, 1.5, 2.0, 0.5]
        }
    }
}

final class AudioEnhancementEngine {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 5)
    private var file: AVAudioFile?
    private var positionFrame: AVAudioFramePosition = 0
    private var durationFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 44100
    private(set) var isPlaying = false
    private let meterLock = NSLock()
    private var meterValue: Double = 0
    private var completed = false
    private var revision: UInt64 = 0

    init() {
        engine.attach(node)
        engine.attach(eq)
        for (index, hz) in [80.0, 250.0, 1000.0, 3500.0, 10000.0].enumerated() {
            let band = eq.bands[index]
            band.filterType = .parametric
            band.frequency = Float(hz)
            band.bandwidth = 0.9
            band.gain = 0
            band.bypass = false
        }
        eq.globalGain = -3
        // El tap solo calcula RMS; no hace FFT ni crea imágenes en el hilo de audio.
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self = self, let samples = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Double = 0
            let channels = Int(buffer.format.channelCount)
            for channel in 0..<channels {
                let data = samples[channel]
                var local: Double = 0
                for index in stride(from: 0, to: frames, by: 8) {
                    let x = Double(data[index]); local += x * x
                }
                sum += local / Double(max(1, (frames + 7) / 8))
            }
            let rms = sqrt(sum / Double(max(channels, 1)))
            self.meterLock.lock()
            self.meterValue = min(1, max(0, rms * 3.5))
            self.meterLock.unlock()
        }
    }

    var duration: Double { Double(durationFrames) / sampleRate }
    var currentTime: Double {
        guard isPlaying, let render = node.lastRenderTime,
              let time = node.playerTime(forNodeTime: render) else {
            return Double(positionFrame) / sampleRate
        }
        return min(duration, Double(positionFrame + time.sampleTime) / sampleRate)
    }
    var level: Double {
        meterLock.lock(); defer { meterLock.unlock() }
        return meterValue
    }
    var reachedEnd: Bool {
        meterLock.lock(); defer { meterLock.unlock() }
        return completed
    }

    func setProfile(_ profile: AudioProfile) {
        for (band, gain) in zip(eq.bands, profile.gains) { band.gain = gain }
        // Reserva de margen para las bandas que amplifican; no es un limitador.
        eq.globalGain = profile == .flat ? 0 : -4
    }

    func setVolume(_ value: Double) { node.volume = Float(min(1, max(0, value))) }

    func load(url: URL, profile: AudioProfile, volume: Double) throws {
        stop()
        let audioFile = try AVAudioFile(forReading: url)
        file = audioFile
        sampleRate = audioFile.processingFormat.sampleRate
        durationFrames = audioFile.length
        guard sampleRate > 0, durationFrames > 0 else {
            throw NSError(domain: "MusicaLocal.Audio", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Archivo sin muestras de audio decodificables"])
        }
        engine.disconnectNodeOutput(node)
        engine.disconnectNodeOutput(eq)
        engine.connect(node, to: eq, format: audioFile.processingFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: audioFile.processingFormat)
        setProfile(profile)
        setVolume(volume)
        try engine.start()
        schedule(from: 0)
        node.play()
        isPlaying = true
    }

    private func schedule(from frame: AVAudioFramePosition) {
        guard let file = file else { return }
        meterLock.lock()
        revision &+= 1
        let currentRevision = revision
        meterLock.unlock()
        positionFrame = min(max(frame, 0), durationFrames)
        meterLock.lock(); completed = false; meterValue = 0; meterLock.unlock()
        let remaining = durationFrames - positionFrame
        guard remaining > 0 else {
            meterLock.lock(); completed = true; meterLock.unlock()
            return
        }
        // scheduleSegment acepta AVAudioFrameCount; las canciones habituales caben en UInt32.
        let length = AVAudioFrameCount(min(remaining, AVAudioFramePosition(UInt32.max)))
        node.scheduleSegment(file, startingFrame: positionFrame, frameCount: length,
                             at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self = self else { return }
            self.meterLock.lock()
            if self.revision == currentRevision { self.completed = true }
            self.meterLock.unlock()
        }
    }

    func pause() {
        guard isPlaying else { return }
        let frame = AVAudioFramePosition(currentTime * sampleRate)
        node.pause()
        positionFrame = frame
        isPlaying = false
    }
    func resume() {
        guard !isPlaying, file != nil else { return }
        // Al pausar, playerTime reinicia la referencia temporal; reprogramamos.
        node.stop()
        schedule(from: positionFrame)
        if !engine.isRunning { try? engine.start() }
        node.play()
        isPlaying = true
    }
    func seek(_ time: Double) {
        node.stop()
        let newFrame = AVAudioFramePosition(min(max(time, 0), duration) * sampleRate)
        schedule(from: newFrame)
        if isPlaying { node.play() }
    }
    func stop() {
        meterLock.lock(); revision &+= 1; meterLock.unlock()
        node.stop()
        engine.stop()
        file = nil
        isPlaying = false
        positionFrame = 0
        durationFrames = 0
        meterLock.lock(); meterValue = 0; completed = false; meterLock.unlock()
    }
    deinit {
        stop()
        engine.mainMixerNode.removeTap(onBus: 0)
    }
}
