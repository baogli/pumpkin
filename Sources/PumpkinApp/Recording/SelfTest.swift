// Adapted from baogli/able-recorder (MIT); see THIRD_PARTY_NOTICES.md.
import AppKit
import AVFoundation
import CoreMedia

enum SelfTest {
    static func require(_ condition: Bool, _ message: String) throws { if !condition { throw RecorderError(message: "TEST FAILED: " + message) } }
    static func ready(_ input: AVAssetWriterInput, movie: MovieWriter, stage: String) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !input.isReadyForMoreMediaData {
            try require(Date() < deadline, "Encoder readiness timeout at \(stage); status \(movie.writer.status.rawValue); \(movie.writer.error?.localizedDescription ?? "no error")")
            try require(movie.writer.status == .writing, "Writer failed at \(stage)")
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
    static func videoSample(frame: Int, fps: Int) throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel)
        guard status == kCVReturnSuccess, let pixel else { throw RecorderError(message: "PixelBuffer") }
        CVPixelBufferLockBaseAddress(pixel, [])
        let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        for y in 0..<180 { for x in 0..<320 { let p = base.advanced(by: y * stride + x * 4); p[0] = UInt8((x + frame * 2) % 256); p[1] = UInt8(y); p[2] = UInt8(frame % 256); p[3] = 255 } }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixel, formatDescriptionOut: &format)
        var time = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(fps)), presentationTimeStamp: CMTime(value: Int64(frame), timescale: Int32(fps)), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixel, formatDescription: format!, sampleTiming: &time, sampleBufferOut: &sample)
        guard let sample else { throw RecorderError(message: "Video sample") }; return sample
    }
    static func run(folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var report: [[String: Any]] = []
        for (name, hevc, fps, rate) in [("h264-30", false, 30, 48000.0), ("h264-60", false, 60, 44100.0), ("hevc-30", true, 30, 96000.0)] {
            let url = folder.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(6)).mp4")
            let movie = try MovieWriter(url: url, width: 320, height: 180, fps: fps, bitrate: 2_000_000, hevc: hevc, audioRate: rate)
            movie.start = .zero; movie.writer.startSession(atSourceTime: .zero)
            fputs("Testing \(name): writer started\n", stderr)
            for frame in 0..<(fps * 2) {
                try await ready(movie.video, movie: movie, stage: "video \(frame)")
                try movie.appendVideo(videoSample(frame: frame, fps: fps))
                let n = Int(rate) / fps
                let data = (0..<(n * 2)).map { i -> Float in
                    let t = Double(frame * n + i / 2) / rate
                    return Float(sin(2 * .pi * (i % 2 == 0 ? 1000 : 1500) * t) * (i % 2 == 0 ? 0.4 : 0.2))
                }
                try await ready(movie.audio!, movie: movie, stage: "audio \(frame)")
                try data.withUnsafeBufferPointer { try movie.appendAudio(pcmSample(samples: $0.baseAddress!, frames: n, rate: rate, time: CMTime(value: Int64(frame * n), timescale: Int32(rate)))) }
                try await Task.sleep(nanoseconds: UInt64(1_000_000_000 / fps))
            }
            try await ready(movie.video, movie: movie, stage: "finish video")
            fputs("Testing \(name): finishing\n", stderr)
            let result: Result<URL, Error> = await withCheckedContinuation { continuation in
                movie.finish(at: CMTime(seconds: 2.5, preferredTimescale: 48000)) { continuation.resume(returning: $0) }
            }
            let finished = try result.get()
            let entry = try await inspect(finished)
            report.append(entry)
            print("PASS \(name): \(entry)")
            try require(movie.videoDrops == 0 && movie.audioDrops == 0, "unexpected drops")
        }
        let noFrames = try MovieWriter(url: folder.appendingPathComponent("no-frames-\(UUID().uuidString.prefix(6)).mp4"), width: 320, height: 180, fps: 30, bitrate: 2_000_000, hevc: false, audioRate: 48000)
        let empty: Result<URL, Error> = await withCheckedContinuation { continuation in noFrames.finish(at: .zero) { continuation.resume(returning: $0) } }
        if case .success = empty { throw RecorderError(message: "Empty recording was accepted") }
        let json = try JSONSerialization.data(withJSONObject: ["timestamp": ISO8601DateFormatter().string(from: Date()), "tests": report, "emptyRecordingRejected": true], options: [.prettyPrinted, .sortedKeys])
        try json.write(to: folder.appendingPathComponent("report.json"))
    }
    static func inspect(_ url: URL) async throws -> [String: Any] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        try require(videoTracks.count == 1 && audioTracks.count == 1, "one video and stereo audio track")
        let size = try await videoTracks[0].load(.naturalSize)
        try require(size.width == 320 && size.height == 180, "video size")
        try require(abs(duration - 2.5) < 0.04, "static-frame stop duration: \(duration)")
        let compressed = try await audioTracks[0].load(.formatDescriptions)
        try require(CMFormatDescriptionGetMediaSubType(compressed[0]) == kAudioFormatMPEG4AAC, "AAC track")
        let reader = try AVAssetReader(asset: asset)
        let videoOut = AVAssetReaderTrackOutput(track: videoTracks[0], outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        let audioOut = AVAssetReaderTrackOutput(track: audioTracks[0], outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false])
        reader.add(videoOut); reader.add(audioOut)
        try require(reader.startReading(), "start decoder")
        var videoCount = 0
        while let sample = videoOut.copyNextSampleBuffer() { try require(sample.imageBuffer != nil, "decoded video"); videoCount += 1 }
        var samples: [Float] = [], rate = 0.0, channels = 0
        while let sample = audioOut.copyNextSampleBuffer() {
            if let desc = sample.formatDescription, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) { rate = asbd.pointee.mSampleRate; channels = Int(asbd.pointee.mChannelsPerFrame) }
            guard let block = sample.dataBuffer else { throw RecorderError(message: "decoded audio buffer") }
            let count = CMBlockBufferGetDataLength(block) / 4
            var values = [Float](repeating: 0, count: count)
            let code = values.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 4, destination: $0.baseAddress!) }
            try require(code == noErr, "decode PCM copy")
            samples.append(contentsOf: values)
        }
        try require(reader.status == .completed, "decode all tracks: \(reader.error?.localizedDescription ?? "")")
        try require(videoCount >= 60, "video frame count")
        try require(channels == 2 && rate == 48000, "AAC stereo 48kHz")
        let frames = samples.count / 2
        try require(frames > 90000 && frames < 101000, "audio length: \(frames)")
        func amplitude(channel: Int, frequency: Double) -> Double {
            var cosine = 0.0, sine = 0.0
            for i in 2000..<min(frames, 94000) {
                let phase = 2 * Double.pi * frequency * Double(i) / rate, v = Double(samples[i * 2 + channel])
                cosine += v * cos(phase); sine += v * sin(phase)
            }
            return 2 * hypot(cosine, sine) / Double(min(frames, 94000) - 2000)
        }
        let l = amplitude(channel: 0, frequency: 1000), r = amplitude(channel: 1, frequency: 1500)
        let crossL = amplitude(channel: 0, frequency: 1500), crossR = amplitude(channel: 1, frequency: 1000)
        try require(l > 0.35 && l < 0.45 && r > 0.17 && r < 0.23, "stereo level: \(l), \(r)")
        try require(crossL < 0.005 && crossR < 0.005, "stereo cross-talk")
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        var offset = 0, atoms: [String: Int] = [:]
        while offset + 8 <= bytes.count {
            var length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let name = String(data: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            if length == 1, offset + 16 <= bytes.count { length = (0..<8).reduce(0) { ($0 << 8) | Int(bytes[offset + 8 + $1]) } }
            if length == 0 { length = bytes.count - offset }
            try require(length >= 8 && offset + length <= bytes.count, "MP4 atom boundaries")
            atoms[name] = offset; offset += length
        }
        try require(atoms["moov"] != nil && atoms["mdat"] != nil && atoms["moov"]! < atoms["mdat"]!, "fast-start MP4")
        return ["file": url.lastPathComponent, "duration": duration, "videoFramesDecoded": videoCount, "audioFramesDecoded": frames,
                "left1000HzAmplitude": l, "right1500HzAmplitude": r, "left1500HzLeak": crossL, "right1000HzLeak": crossR, "fastStart": true, "bytes": bytes.count]
    }
}
