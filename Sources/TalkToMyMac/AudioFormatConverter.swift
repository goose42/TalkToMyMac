import AVFoundation

/// Converts in-memory Float32 mono audio into an `AVAudioPCMBuffer` matching an
/// arbitrary target format, resampling with `AVAudioConverter` when needed.
///
/// Generalized from the app's original hardcoded 16 kHz resample so each consumer
/// (currently just speech transcription) can ask for whatever format it actually wants.
enum AudioFormatConverter {
    enum ConversionError: Error {
        case formatCreationFailed
        case bufferAllocationFailed
        case converterCreationFailed
    }

    /// Wraps `samples` (mono, captured at `sampleRate`) into a PCM buffer, converting
    /// to `targetFormat` if it differs from the source format.
    static func convert(samples: [Float], sampleRate: Double, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw ConversionError.formatCreationFailed
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw ConversionError.bufferAllocationFailed
        }
        memcpy(sourceBuffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)
        sourceBuffer.frameLength = frameCount

        // Already matches the target — nothing to convert.
        if sourceFormat.sampleRate == targetFormat.sampleRate,
           sourceFormat.channelCount == targetFormat.channelCount,
           sourceFormat.commonFormat == targetFormat.commonFormat {
            return sourceBuffer
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw ConversionError.converterCreationFailed
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(frameCount) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrames) else {
            throw ConversionError.bufferAllocationFailed
        }

        var conversionError: NSError?
        var inputConsumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        if let err = conversionError { throw err }

        return outputBuffer
    }
}
