// §D42's physical lip-sync rig: a full-screen flash and a 1 kHz beep at the
// same instant, every argv[1] s, argv[2] times. Point a camera at the screen
// (or a lit room), broadcast to a local server, and compare onsets.
import AppKit
import AVFoundation
// Full-screen black window; every `period` s the screen goes white and a
// 1 kHz beep plays, both for 120 ms, scheduled for the same instant.
let period = Double(CommandLine.arguments.dropFirst().first ?? "3") ?? 3
let count = Int(CommandLine.arguments.dropFirst(2).first ?? "20") ?? 20
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let screen = NSScreen.main!
let win = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
win.level = .screenSaver
win.backgroundColor = .black
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
engine.attach(player)
let fmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
engine.connect(player, to: engine.mainMixerNode, format: fmt)
try! engine.start()
player.play()
let n = AVAudioFrameCount(48000 * 0.12)
let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
buf.frameLength = n
for c in 0..<2 { let p = buf.floatChannelData![c]; for i in 0..<Int(n) { p[i] = Float(sin(2 * .pi * 1000 * Double(i) / 48000) * 0.8) } }
var k = 0
Timer.scheduledTimer(withTimeInterval: period, repeats: true) { t in
    k += 1
    if k > count { app.terminate(nil) }
    // Audio output latency is a few ms on built-in speakers; display ~1 frame.
    player.scheduleBuffer(buf, at: nil)
    win.backgroundColor = .white
    print(String(format: "flash %d at %.3f", k, ProcessInfo.processInfo.systemUptime)); fflush(stdout)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { win.backgroundColor = .black }
}
app.run()
