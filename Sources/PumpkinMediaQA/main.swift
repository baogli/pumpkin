import AppKit
import AVFoundation
@testable import PumpkinApp

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/PumpkinMediaQA", isDirectory: true)
setvbuf(stdout, nil, _IONBF, 0)
Task {
    do {
        try await SelfTest.run(folder: output)
        var report: [[String: Any]] = []
        for (name, hevc) in [("video-only-h264", false), ("video-only-hevc", true)] {
            let url = output.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(6)).mp4")
            let movie = try MovieWriter(url: url, width: 320, height: 180, fps: 30, bitrate: 2_000_000, hevc: hevc, audioRate: nil, realtime: false)
            for frame in 0..<60 {
                try await SelfTest.ready(movie.video, movie: movie, stage: name)
                try movie.appendVideo(SelfTest.videoSample(frame: frame, fps: 30))
            }
            try await SelfTest.ready(movie.video, movie: movie, stage: "finish")
            let result: Result<URL, Error> = await withCheckedContinuation { continuation in movie.finish(at: CMTime(seconds: 2.5, preferredTimescale: 48000)) { continuation.resume(returning: $0) } }
            let finished = try result.get(), asset = AVURLAsset(url: finished)
            let audio = try await asset.loadTracks(withMediaType: .audio), video = try await asset.loadTracks(withMediaType: .video), duration = try await asset.load(.duration).seconds
            try SelfTest.require(audio.isEmpty && video.count == 1 && duration >= 2.45 && duration <= 2.6, "video-only tracks / duration")
            let reader = try AVAssetReader(asset: asset)
            let decoded = AVAssetReaderTrackOutput(track: video[0], outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            reader.add(decoded); try SelfTest.require(reader.startReading(), "video-only reader start")
            var frames = 0
            while decoded.copyNextSampleBuffer() != nil { frames += 1 }
            try SelfTest.require(reader.status == .completed && frames >= 60, "video-only full decode")
            let entry: [String: Any] = ["file": finished.lastPathComponent, "duration": duration, "videoFramesDecoded": frames, "audioTracks": 0]
            report.append(entry); print("PASS \(name): \(entry)")
        }
        try JSONSerialization.data(withJSONObject: ["videoOnly": report], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("video-only-report.json"))
        print("MEDIA QA PASSED: three stereo cases and two video-only cases")
        exit(0)
    } catch { fputs("MEDIA QA FAILED: \(error.localizedDescription)\n", stderr); exit(1) }
}
DispatchQueue.global().asyncAfter(deadline: .now() + 60) { fputs("MEDIA QA TIMEOUT\n", stderr); exit(2) }
RunLoop.main.run()
