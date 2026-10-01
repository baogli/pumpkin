// Adapted from baogli/able-recorder (MIT); see THIRD_PARTY_NOTICES.md.
import PumpkinAudioBridge
import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

struct VideoPreset {
    let title: String
    let bitsPerPixel: Double
    static let all = [VideoPreset(title: "Компактное", bitsPerPixel: 0.07), VideoPreset(title: "Сбалансированное", bitsPerPixel: 0.13), VideoPreset(title: "Высокое", bitsPerPixel: 0.25)]
    func bitrate(width: Int, height: Int, fps: Int) -> Int {
        max(1_500_000, min(60_000_000, Int(Double(width * height * fps) * bitsPerPixel)))
    }
}

func pcmSample(samples: UnsafePointer<Float>, frames: Int, rate: Double, time: CMTime) throws -> CMSampleBuffer {
    var asbd = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
        mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    var format: CMAudioFormatDescription?
    var status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
    guard status == noErr, let format else { throw RecorderError(message: "Формат звука: \(status)") }
    var block: CMBlockBuffer?
    let bytes = frames * 8
    status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
    guard status == noErr, let block else { throw RecorderError(message: "Буфер звука: \(status)") }
    status = CMBlockBufferReplaceDataBytes(with: samples, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
    guard status == noErr else { throw RecorderError(message: "Копирование звука: \(status)") }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(rate)), presentationTimeStamp: time, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
    guard status == noErr, let sample else { throw RecorderError(message: "Аудиопакет: \(status)") }
    return sample
}

// All writer operations and HAL ring consumption run on the same serial queue.
final class MovieWriter {
    let writer: AVAssetWriter
    let video: AVAssetWriterInput
    let audio: AVAssetWriterInput?
    let finalURL: URL
    let partialURL: URL
    let fps: Int
    var start: CMTime?
    var lastVideo: CMSampleBuffer?
    var lastAudioEnd: CMTime?
    var videoFrames = 0, audioFrames = 0, videoDrops = 0, audioDrops = 0

    init(url: URL, width: Int, height: Int, fps: Int, bitrate: Int, hevc: Bool, audioRate: Double?, realtime: Bool = true) throws {
        self.finalURL = url; self.fps = fps
        partialURL = url.deletingPathExtension().appendingPathExtension("partial.mp4")
        writer = try AVAssetWriter(outputURL: partialURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                       AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                       AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2, AVVideoAllowFrameReorderingKey: false]])
        if let audioRate {
        var asbd = AudioStreamBasicDescription(mSampleRate: audioRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
            mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var hint: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &hint)
        audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256000], sourceFormatHint: hint)
        } else { audio = nil }
        video.expectsMediaDataInRealTime = realtime
        guard writer.canAdd(video) else { throw RecorderError(message: "Этот формат видео недоступен.") }
        writer.add(video)
        if let audio {
            audio.expectsMediaDataInRealTime = realtime
            guard writer.canAdd(audio) else { throw RecorderError(message: "Этот формат звука недоступен.") }
            writer.add(audio)
        }
        guard writer.startWriting() else { throw writer.error ?? RecorderError(message: "Не удалось открыть MP4.") }
    }
    func appendVideo(_ sample: CMSampleBuffer) throws {
        guard sample.isValid, sample.imageBuffer != nil else { return }
        let pts = sample.presentationTimeStamp
        guard pts.isNumeric else { return }
        if let lastVideo, pts <= lastVideo.presentationTimeStamp { return }
        if start == nil { start = pts; writer.startSession(atSourceTime: pts) }
        guard video.isReadyForMoreMediaData else { videoDrops += 1; return }
        guard video.append(sample) else { throw writer.error ?? RecorderError(message: "Ошибка записи видео.") }
        lastVideo = sample; videoFrames += 1
    }
    func appendAudio(_ sample: CMSampleBuffer) throws {
        guard let audio, let start, sample.presentationTimeStamp >= start else { return }
        if let lastAudioEnd, sample.presentationTimeStamp < lastAudioEnd - CMTime(value: 2, timescale: 48000) { return }
        guard audio.isReadyForMoreMediaData else { audioDrops += 1; return }
        guard audio.append(sample) else { throw writer.error ?? RecorderError(message: "Ошибка записи звука.") }
        lastAudioEnd = sample.presentationTimeStamp + sample.duration
        audioFrames += sample.numSamples
    }
    func finish(at end: CMTime, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let start, let lastVideo else {
            writer.cancelWriting()
            completion(.failure(RecorderError(message: "Нет кадров экрана. Проверь разрешение на запись экрана."))); return
        }
        let finishTime = max(end, lastAudioEnd ?? start)
        // Extend a static desktop to the real stop time, even if SCK sends idle frames.
        let finalPTS = finishTime - CMTime(value: 1, timescale: Int32(fps))
        if finalPTS > lastVideo.presentationTimeStamp, video.isReadyForMoreMediaData {
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(fps)), presentationTimeStamp: finalPTS, decodeTimeStamp: .invalid)
            var copy: CMSampleBuffer?
            if CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: lastVideo, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy) == noErr, let copy { _ = video.append(copy) }
        }
        writer.endSession(atSourceTime: finishTime)
        video.markAsFinished(); audio?.markAsFinished()
        writer.finishWriting { [self] in
            guard writer.status == .completed else { completion(.failure(writer.error ?? RecorderError(message: "Не удалось завершить MP4. Частичный файл сохранён."))); return }
            do { try FileManager.default.moveItem(at: partialURL, to: finalURL); completion(.success(finalURL)) }
            catch { completion(.failure(error)) }
        }
    }
}

final class HardwareAudio {
    private var handle: OpaquePointer?
    private var timer: DispatchSourceTimer?
    private let device: InputDevice
    private var lastMeter = Date.distantPast
    private var lastPacket = Date()
    var packets: UInt64 = 0
    var onSample: ((CMSampleBuffer) -> Void)?
    var onMeter: ((Float, Float, UInt64) -> Void)?
    var onFailure: ((Error) -> Void)?
    init(device: InputDevice) { self.device = device }
    func start(left: Int, right: Int, queue: DispatchQueue) throws {
        guard left >= 1, right >= 1, left <= device.channels, right <= device.channels, device.rate > 0 else { throw RecorderError(message: "Недоступная пара каналов.") }
        var code: Int32 = 0
        guard let pointer = lr_audio_start(device.id, Int32(left - 1), Int32(right - 1), device.rate, &code) else { throw RecorderError(message: "Не удалось открыть \(device.name), входы \(left)/\(right). Core Audio: \(code). Проверь разрешение «Микрофон».") }
        handle = pointer; lastPacket = Date()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in self?.drain() }
        timer = source; source.resume()
    }
    private func drain() {
        guard let handle else { return }
        var packet = LRPacket()
        var left: Float = 0, right: Float = 0
        while lr_audio_peek(handle, &packet) != 0 {
            defer { lr_audio_pop(handle) }
            guard let data = packet.samples else { continue }
            for i in 0..<Int(packet.frames) { left = max(left, abs(data[i * 2])); right = max(right, abs(data[i * 2 + 1])) }
            packets += 1; lastPacket = Date()
            if let onSample {
                do { onSample(try pcmSample(samples: data, frames: Int(packet.frames), rate: device.rate, time: CMClockMakeHostTimeFromSystemUnits(packet.hostTime))) }
                catch { onFailure?(error) }
            }
        }
        if Date().timeIntervalSince(lastMeter) > 0.1 {
            lastMeter = Date()
            onMeter?(left, right, lr_audio_dropped(handle))
            let code = lr_audio_error(handle)
            if code != 0 { onFailure?(RecorderError(message: "Аудиокарта вернула ошибку \(code).")) }
            else if Date().timeIntervalSince(lastPacket) > 3 || !Devices.alive(device.id) { onFailure?(RecorderError(message: "Аудиокарта перестала передавать звук. Проверь подключение.")) }
            else if abs(Devices.rate(device.id) - device.rate) > 1 { onFailure?(RecorderError(message: "Частота аудиокарты изменилась. Начни новую запись.")) }
        }
    }
    func stop() { timer?.cancel(); timer = nil; if let handle { lr_audio_stop(handle) }; handle = nil }
    deinit { if let handle { lr_audio_stop(handle) } }
}

final class RecordingSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.pumpkin.media", qos: .userInitiated)
    private var stream: SCStream?
    private var hardware: HardwareAudio?
    private var movie: MovieWriter?
    private var stopping = false
    var onMeter: ((Float, Float, UInt64) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onStats: ((Int, Int, Int) -> Void)?
    func monitor(device: InputDevice, left: Int, right: Int) throws {
        try queue.sync {
            let input = HardwareAudio(device: device)
            input.onMeter = onMeter; input.onFailure = { [weak self] error in self?.onFailure?(error) }
            try input.start(left: left, right: right, queue: queue); hardware = input
        }
    }
    func start(display: SCDisplay, device: InputDevice?, left: Int, right: Int, width: Int, height: Int, fps: Int, bitrate: Int, hevc: Bool, cursor: Bool, url: URL, content: SCShareableContent) async throws {
        let config = SCStreamConfiguration()
        config.width = width; config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
        config.queueDepth = 5; config.showsCursor = cursor; config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let capture = SCStream(filter: filter, configuration: config, delegate: self)
        try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try queue.sync {
            movie = try MovieWriter(url: url, width: width, height: height, fps: fps, bitrate: bitrate, hevc: hevc, audioRate: device?.rate)
            if let device {
            let input = HardwareAudio(device: device)
            input.onMeter = onMeter; input.onFailure = { [weak self] error in self?.onFailure?(error) }
            input.onSample = { [weak self] sample in
                guard let self, !stopping else { return }
                do { try movie?.appendAudio(sample) } catch { onFailure?(error) }
            }
            try input.start(left: left, right: right, queue: queue); hardware = input
            }
        }
        stream = capture
        do { try await capture.startCapture() }
        catch { queue.sync { hardware?.stop(); hardware = nil; movie?.writer.cancelWriting(); movie = nil }; stream = nil; throw error }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard !stopping, outputType == .screen, sampleBuffer.isValid else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int, raw != SCFrameStatus.complete.rawValue { return }
        do { try movie?.appendVideo(sampleBuffer); if let movie { onStats?(movie.videoFrames, movie.videoDrops, movie.audioDrops) } }
        catch { onFailure?(error) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [weak self] in guard let self, !stopping else { return }; onFailure?(error) }
    }
    func stop() async -> (Result<URL, Error>?, String) {
        queue.sync { stopping = true; hardware?.stop(); hardware = nil }
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        if let stream { try? await stream.stopCapture() }; stream = nil
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let movie else { continuation.resume(returning: (nil, "")); return }
                let summary = "\(movie.videoFrames) кадров; пропуски: видео \(movie.videoDrops), аудио \(movie.audioDrops)."
                movie.finish(at: end) { result in continuation.resume(returning: (result, summary)) }
                self.movie = nil
            }
        }
    }
}
