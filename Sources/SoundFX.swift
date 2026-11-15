import AVFoundation

/// Synthesizes don/ka sounds in code (no asset files) and plays them through
/// AVAudioEngine with a small pool of player nodes for low latency.
final class SoundFX {
    static let shared = SoundFX()

    private let engine = AVAudioEngine()
    private var nodes: [AVAudioPlayerNode] = []
    private var next = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var donBuf: AVAudioPCMBuffer?
    private var kaBuf: AVAudioPCMBuffer?
    private var configured = false

    private init() {}

    func configure() {
        guard !configured else { return }
        configured = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)

        donBuf = makeBuffer(freq: 170, dur: 0.20, decay: 22, noise: 0.12, drop: true)
        kaBuf = makeBuffer(freq: 2300, dur: 0.09, decay: 55, noise: 0.55, drop: false)

        for _ in 0..<8 {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: format)
            nodes.append(n)
        }
        startEngine()
    }

    private func startEngine() {
        if !engine.isRunning { try? engine.start() }
        for n in nodes where !n.isPlaying { n.play() }
    }

    func play(don: Bool) {
        if !engine.isRunning { startEngine() }
        guard let buf = don ? donBuf : kaBuf, !nodes.isEmpty else { return }
        let vol = UserDefaults.standard.object(forKey: "seVol") as? Double ?? 0.8
        engine.mainMixerNode.outputVolume = Float(vol)
        let node = nodes[next]
        next = (next + 1) % nodes.count
        node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    private func makeBuffer(freq: Float, dur: Float, decay: Float, noise: Float, drop: Bool) -> AVAudioPCMBuffer? {
        let rate: Float = 44100
        let count = Int(rate * dur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let ch = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(count)
        for i in 0..<count {
            let t = Float(i) / rate
            let env = expf(-t * decay)
            let bend: Float = drop ? (1 + 0.6 * expf(-t * 30)) : 1
            let tone = sinf(2 * Float.pi * freq * bend * t)
            let n = Float.random(in: -1...1)
            ch[i] = env * (tone * (1 - noise) + n * noise) * 0.85
        }
        return buf
    }
}
