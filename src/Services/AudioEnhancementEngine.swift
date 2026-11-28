// Motor experimental de audio. macOS 12 / Swift 5.7.
// No sustituye el motor AVAudioPlayer: se usa solo si el usuario lo activa.
import Foundation
import AVFoundation
import AudioAtomics

enum AudioProfile: String, CaseIterable, Identifiable {
    case flat, balanced, bass, vocals
    case rock, pop, jazz, classical, electronic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .flat: return "Original"
        case .balanced: return "Equilibrado"
        case .bass: return "Graves"
        case .vocals: return "Voces"
        case .rock: return "Rock"
        case .pop: return "Pop"
        case .jazz: return "Jazz"
        case .classical: return "Clásica"
        case .electronic: return "Electrónica"
        }
    }
    var gains: [Float] {
        switch self {
        case .flat: return [0, 0, 0, 0, 0]
        case .balanced: return [1.0, 0.5, 0, 0.7, 0.9]
        case .bass: return [3.0, 2.0, -0.5, 0, 0]
        case .vocals: return [-1.0, -0.5, 1.5, 2.0, 0.5]
        case .rock: return [3, 1.5, -1, 2, 2.5]
        case .pop: return [0.5, -0.5, 1.5, 2, 1]
        case .jazz: return [1.5, 0.5, 0, -0.5, 2]
        case .classical: return [1, 0, 0, 0.5, 1.5]
        case .electronic: return [3.5, 1, -1, 0.5, 3]
        }
    }
}

// Los callbacks retienen solo el dato compartido, con memoria asignada antes de iniciarlos.
private final class AudioAtomicValue {
    private let storage = audio_atomic_create()!

    var value: UInt64 {
        get { audio_atomic_load(storage) }
        set { audio_atomic_store(storage, newValue) }
    }

    func clear(ifEqualTo expected: UInt64) {
        audio_atomic_clear_if_equal(storage, expected)
    }

    deinit { audio_atomic_destroy(storage) }
}

final class AudioEnhancementEngine {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 5)
    private var file: AVAudioFile?
    private var segmentStart: AVAudioFramePosition = 0
    private var pausedTime: Double = 0
    private var durationFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 44100
    private(set) var isPlaying = false
    private let meter = AudioAtomicValue()
    // Cero indica que terminó la programación vigente. Cada búsqueda usa una revisión distinta.
    private let pendingRevision = AudioAtomicValue()
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
        // El tap solo calcula RMS; no hace FFT ni crea imágenes en el hilo de audio.
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [meter] buffer, _ in
            guard let samples = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Double = 0
            let channels = Int(buffer.format.channelCount)
            let sampleStride = buffer.stride
            for channel in 0..<channels {
                let data = samples[channel]
                var local: Double = 0
                for index in stride(from: 0, to: frames, by: 8) {
                    let x = Double(data[index * sampleStride])
                    local += x * x
                }
                sum += local / Double(max(1, (frames + 7) / 8))
            }
            let rms = sqrt(sum / Double(max(channels, 1)))
            meter.value = min(1, max(0, rms * 3.5)).bitPattern
        }
    }

    var duration: Double { Double(durationFrames) / sampleRate }
    var currentTime: Double {
        guard isPlaying else { return pausedTime }
        if reachedEnd { return duration }
        guard let render = node.lastRenderTime,
              let time = node.playerTime(forNodeTime: render), time.isSampleTimeValid,
              time.sampleRate > 0 else { return pausedTime }
        let elapsed = Double(max(time.sampleTime, 0)) / time.sampleRate
        return min(duration, max(pausedTime, Double(segmentStart) / sampleRate + elapsed))
    }

    var level: Double { isPlaying && !reachedEnd ? Double(bitPattern: meter.value) : 0 }
    var reachedEnd: Bool { file != nil && pendingRevision.value == 0 }

    func setProfile(_ profile: AudioProfile) {
        for (band, gain) in zip(eq.bands, profile.gains) { band.gain = gain }
        // Reserva de margen para las bandas que amplifican; no es un limitador.
        eq.globalGain = profile == .flat ? 0 : -4
    }

    func setVolume(_ value: Double) { node.volume = Float(min(1, max(0, value))) }

    func load(url: URL, profile: AudioProfile, volume: Double, position: Double = 0) throws {
        stop()
        let audioFile = try AVAudioFile(forReading: url)
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
        file = audioFile
        seek(position)
    }

    private func schedule(from frame: AVAudioFramePosition, in file: AVAudioFile) {
        // Invalidar antes de stop(), que también puede disparar callbacks pendientes.
        revision &+= 1
        if revision == 0 { revision = 1 }
        let currentRevision = revision
        pendingRevision.value = frame < durationFrames ? currentRevision : 0
        node.stop()
        meter.value = 0
        segmentStart = frame
        pausedTime = Double(frame) / sampleRate

        var start = frame
        while start < durationFrames {
            let length = min(durationFrames - start, AVAudioFramePosition(AVAudioFrameCount.max))
            let isLast = start + length == durationFrames
            node.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(length),
                                 at: nil, completionCallbackType: .dataPlayedBack,
                                 completionHandler: isLast ? { [pendingRevision] _ in
                pendingRevision.clear(ifEqualTo: currentRevision)
            } : nil)
            start += length
        }
    }

    func pause() {
        guard isPlaying else { return }
        pausedTime = currentTime
        node.pause()
        isPlaying = false
        meter.value = 0
    }

    @discardableResult
    func resume() -> Bool {
        guard file != nil else { return false }
        if isPlaying { return true }
        if !reachedEnd {
            if !engine.isRunning {
                do { try engine.start() }
                catch { return false }
            }
            node.play()
        }
        isPlaying = true
        return true
    }

    func seek(_ time: Double) {
        guard let file = file, !time.isNaN else { return }
        let wasPlaying = isPlaying
        isPlaying = false
        let frame = time >= duration ? durationFrames : AVAudioFramePosition(max(time, 0) * sampleRate)
        schedule(from: frame, in: file)
        if wasPlaying { resume() }
    }

    func stop() {
        pendingRevision.value = 0
        node.stop()
        engine.stop()
        file = nil
        isPlaying = false
        segmentStart = 0
        pausedTime = 0
        durationFrames = 0
        meter.value = 0
    }

    deinit {
        stop()
        engine.mainMixerNode.removeTap(onBus: 0)
    }
}
