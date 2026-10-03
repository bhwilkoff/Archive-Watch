// The helper app §8.76 taps: a sine at argv[1] Hz for argv[2] seconds,
// built into an .app bundle (a process tap follows BUNDLE ids) by
// test_studio_all.sh. Restarts its engine when the output device changes
// rate, as a calling app does.
import AVFoundation
let f = Double(CommandLine.arguments.dropFirst().first ?? "1000") ?? 1000
let secs = Double(CommandLine.arguments.dropFirst(2).first ?? "20") ?? 20
let engine = AVAudioEngine()
let fmt = engine.outputNode.outputFormat(forBus: 0)
let sr = fmt.sampleRate
var phase = 0.0
let node = AVAudioSourceNode { _, _, frames, abl -> OSStatus in
    let bufs = UnsafeMutableAudioBufferListPointer(abl)
    for i in 0..<Int(frames) {
        let v = Float(sin(phase) * 0.25); phase += 2 * .pi * f / sr
        for b in bufs { b.mData!.assumingMemoryBound(to: Float.self)[i] = v }
    }
    return noErr
}
engine.attach(node)
engine.connect(node, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sr, channels: fmt.channelCount))
try! engine.start()
NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
    try? engine.start(); print("restarted"); fflush(stdout)
}
print("tone \(f) Hz at \(sr)"); fflush(stdout)
Thread.sleep(forTimeInterval: secs)
