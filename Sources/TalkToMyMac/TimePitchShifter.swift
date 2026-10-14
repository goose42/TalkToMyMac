import AVFoundation
import TalkToMyMacCore

/// Shifts pitch at the same tempo with `AVAudioUnitTimePitch`, rendering offline (manual
/// rendering mode) so it runs faster than real time and never touches the audio hardware.
final class TimePitchShifter: PitchShifting {
    func shift(_ samples: [Float], sampleRate: Double, cents: Int) -> [Float]? {
        do {
            return try render(samples, sampleRate: sampleRate, cents: cents)
        } catch {
            print("[TimePitchShifter] Render failed: \(error)")
            return nil
        }
    }

    private func render(_ samples: [Float], sampleRate: Double, cents: Int) throws -> [Float]? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        let input = try AudioFormatConverter.convert(samples: samples, sampleRate: sampleRate, to: format)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.pitch = Float(cents)
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        let chunk: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunk)
        try engine.start()
        defer { engine.stop() }
        player.scheduleBuffer(input)
        player.play()

        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunk) else {
            return nil
        }
        // Same tempo, so the output is as long as the input.
        var output: [Float] = []
        output.reserveCapacity(samples.count)
        while output.count < samples.count {
            let frames = min(chunk, AVAudioFrameCount(samples.count - output.count))
            switch try engine.renderOffline(frames, to: buffer) {
            case .success:
                output.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0],
                                                              count: Int(buffer.frameLength)))
            default:
                // Offline rendering from a player node has nothing to wait for, so any
                // other status means the render won't make progress.
                return nil
            }
        }
        return output
    }
}
